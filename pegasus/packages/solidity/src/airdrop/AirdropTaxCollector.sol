// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {IAirdropTaxCollector} from "src/interfaces/airdrop/IAirdropTaxCollector.sol";
import {Normalize} from "src/utils/normalize.sol";
import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IUsd0PP} from "src/interfaces/token/IUsd0PP.sol";
import {IAirdropDistribution} from "src/interfaces/airdrop/IAirdropDistribution.sol";

import {
    DEFAULT_ADMIN_ROLE,
    AIRDROP_OPERATOR_ROLE,
    PAUSING_CONTRACTS_ROLE,
    BASIS_POINT_BASE,
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_USD0PP,
    CONTRACT_TREASURY,
    AIRDROP_INITIAL_START_TIME,
    AIRDROP_CLAIMING_PERIOD_LENGTH,
    CONTRACT_AIRDROP_DISTRIBUTION
} from "src/constants.sol";

import {
    NullContract,
    SameValue,
    InvalidClaimingPeriodStartDate,
    InvalidMaxChargeableTax,
    InvalidInputArraysLength,
    AmountIsZero,
    NotInClaimingPeriod,
    ClaimerHasPaidTax,
    AirdropVoided
} from "src/errors.sol";

/// @title AirdropTaxCollector
/// @notice Collects tax from airdrop claimers
/// @author Usual Tech team
contract AirdropTaxCollector is
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IAirdropTaxCollector
{
    using Math for uint256;
    using SafeERC20 for IUsd0PP;
    using Normalize for uint256;
    using CheckAccessControl for IRegistryAccess;

    /// @custom:storage-location erc7201:AirdropTaxCollector.storage.v0
    struct AirdropTaxCollectorStorage {
        /// @notice The RegistryAccess contract instance for role checks.
        IRegistryAccess registryAccess;
        /// @notice The RegistryContract contract instance.
        IRegistryContract registryContract;
        /// @notice The USD0PP contract instance.
        IUsd0PP usd0PP;
        /// @notice The treasury address.
        address treasury;
        /// @notice The maximum chargeable tax used to calculate the tax amount over the claiming period.
        uint256 maxChargeableTax;
        /// @notice Mapping of claimers to whether they have paid tax.
        mapping(address claimer => bool hasPaidTax) taxedClaimers;
        /// @notice Mapping of claimers usd0pp balance during prelaunch that used for the tax amount calculation.
        mapping(address claimer => uint256 usd0PPBalancePrelaunch) prelaunchUsd0ppBalance;
    }

    // keccak256(abi.encode(uint256(keccak256("AirdropTaxCollector.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant AirdropTaxCollectorStorageLocation =
        0xbd7be6fe7da1c000395a8ad24bc3399394168d34547b812a2f9e319a0292f200;

    /// @notice Returns the storage struct of the contract.
    /// @return $ The pointer to the storage struct of the contract.
    function _airdropTaxCollectorStorage()
        internal
        pure
        returns (AirdropTaxCollectorStorage storage $)
    {
        bytes32 position = AirdropTaxCollectorStorageLocation;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := position
        }
    }

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /// @notice Event emitted when a claimer pays tax.
    /// @param account The account that paid the tax.
    /// @param claimTaxAmount The tax amount paid.
    event AirdropTaxPaid(address indexed account, uint256 claimTaxAmount);

    /// @notice Event emitted when the max chargeable tax is set.
    /// @param tax The new max chargeable tax.
    event MaxChargeableTaxSet(uint256 tax);

    /*///////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*///////////////////////////////////////////////////////////////
                                Initializer
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with the registry contract.
    /// @param registryContract The address of the registry contract.
    function initialize(address registryContract) public initializer {
        if (registryContract == address(0)) {
            revert NullContract();
        }

        if (AIRDROP_INITIAL_START_TIME < block.timestamp) {
            revert InvalidClaimingPeriodStartDate();
        }

        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();

        AirdropTaxCollectorStorage storage $ = _airdropTaxCollectorStorage();
        $.registryContract = IRegistryContract(registryContract);
        $.registryAccess = IRegistryAccess($.registryContract.getContract(CONTRACT_REGISTRY_ACCESS));
        $.usd0PP = IUsd0PP($.registryContract.getContract(CONTRACT_USD0PP));
        $.treasury = $.registryContract.getContract(CONTRACT_TREASURY);
        $.maxChargeableTax = BASIS_POINT_BASE;
    }

    /*//////////////////////////////////////////////////////////////
                          Restricted functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAirdropTaxCollector
    function setMaxChargeableTax(uint256 tax) external {
        if (tax == 0) {
            revert InvalidMaxChargeableTax();
        }

        if (tax > BASIS_POINT_BASE) {
            revert InvalidMaxChargeableTax();
        }

        AirdropTaxCollectorStorage storage $ = _airdropTaxCollectorStorage();
        $.registryAccess.onlyMatchingRole(AIRDROP_OPERATOR_ROLE);

        if ($.maxChargeableTax == tax) {
            revert SameValue();
        }

        $.maxChargeableTax = tax;
        emit MaxChargeableTaxSet(tax);
    }

    // @inheritdoc IAirdropTaxCollector
    function setUsd0ppPrelaunchBalances(
        address[] calldata addressesToAllocateTo,
        uint256[] calldata prelaunchBalances
    ) external whenNotPaused {
        AirdropTaxCollectorStorage storage $ = _airdropTaxCollectorStorage();
        $.registryAccess.onlyMatchingRole(AIRDROP_OPERATOR_ROLE);

        if (addressesToAllocateTo.length != prelaunchBalances.length) {
            revert InvalidInputArraysLength();
        }

        for (uint256 i; i < addressesToAllocateTo.length;) {
            if (prelaunchBalances[i] == 0) {
                revert AmountIsZero();
            }
            $.prelaunchUsd0ppBalance[addressesToAllocateTo[i]] = prelaunchBalances[i];

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Pauses the contract.
    /// @dev This function can only be called by a pausing contracts role
    function pause() external {
        AirdropTaxCollectorStorage storage $ = _airdropTaxCollectorStorage();
        $.registryAccess.onlyMatchingRole(PAUSING_CONTRACTS_ROLE);
        _pause();
    }

    /// @notice Unpauses the contract.
    /// @dev This function can only be called by the DEFAULT_ADMIN_ROLE
    function unpause() external {
        AirdropTaxCollectorStorage storage $ = _airdropTaxCollectorStorage();
        $.registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                               Internal
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates the tax amount for the given account.
    /// @param $ The storage struct of the contract.
    /// @param account The account to calculate the tax amount for.
    /// @return claimTaxAmount The tax amount required to be paid to claim airdrop.
    function _calculateClaimTaxAmount(AirdropTaxCollectorStorage storage $, address account)
        internal
        view
        returns (uint256 claimTaxAmount)
    {
        uint256 claimerUsd0PPBalance = $.prelaunchUsd0ppBalance[account];

        uint256 claimingTimeLeft;
        if (block.timestamp > AIRDROP_INITIAL_START_TIME + AIRDROP_CLAIMING_PERIOD_LENGTH) {
            claimingTimeLeft = 0;
        } else {
            claimingTimeLeft =
                AIRDROP_INITIAL_START_TIME + AIRDROP_CLAIMING_PERIOD_LENGTH - block.timestamp;
        }

        uint256 taxFee = $.maxChargeableTax.mulDiv(claimingTimeLeft, AIRDROP_CLAIMING_PERIOD_LENGTH);
        claimTaxAmount = claimerUsd0PPBalance.mulDiv(taxFee, BASIS_POINT_BASE);
    }

    /*//////////////////////////////////////////////////////////////
                               External
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAirdropTaxCollector
    function payTaxAmount() external nonReentrant whenNotPaused {
        _payTaxAmount(msg.sender);
    }

    /// @notice Pays the tax amount for the given account.
    /// @param account The account to pay the tax for.
    /// @dev This function can only be called during the claiming period.
    function _payTaxAmount(address account) internal {
        AirdropTaxCollectorStorage storage $ = _airdropTaxCollectorStorage();

        bool isBeforeStartDate = block.timestamp < AIRDROP_INITIAL_START_TIME;
        bool isAfterEndDate =
            block.timestamp > AIRDROP_INITIAL_START_TIME + AIRDROP_CLAIMING_PERIOD_LENGTH;

        if (isBeforeStartDate || isAfterEndDate) {
            revert NotInClaimingPeriod();
        }

        if ($.taxedClaimers[account]) {
            revert ClaimerHasPaidTax();
        }

        // Check if the account hasn't voided it's eligibility for airdrop
        IAirdropDistribution airdropContract =
            IAirdropDistribution($.registryContract.getContract(CONTRACT_AIRDROP_DISTRIBUTION));
        if (airdropContract.getRagequitStatus(account)) {
            revert AirdropVoided();
        }

        uint256 claimTaxAmount = _calculateClaimTaxAmount($, account);

        $.taxedClaimers[account] = true;
        $.usd0PP.setBondEarlyUnlockDisabled(account);
        emit AirdropTaxPaid(account, claimTaxAmount);

        $.usd0PP.safeTransferFrom(account, $.treasury, claimTaxAmount);
    }

    /*//////////////////////////////////////////////////////////////
                               Getters
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAirdropTaxCollector
    function hasPaidTax(address claimer) external view returns (bool) {
        return _airdropTaxCollectorStorage().taxedClaimers[claimer];
    }

    /// @inheritdoc IAirdropTaxCollector
    function calculateClaimTaxAmount(address account) external view returns (uint256) {
        AirdropTaxCollectorStorage storage $ = _airdropTaxCollectorStorage();

        return _calculateClaimTaxAmount($, account);
    }

    /// @inheritdoc IAirdropTaxCollector
    function getMaxChargeableTax() external view returns (uint256) {
        return _airdropTaxCollectorStorage().maxChargeableTax;
    }

    /// @inheritdoc IAirdropTaxCollector
    function getClaimingPeriod() external pure returns (uint256 startDate, uint256 endDate) {
        return (
            AIRDROP_INITIAL_START_TIME, AIRDROP_INITIAL_START_TIME + AIRDROP_CLAIMING_PERIOD_LENGTH
        );
    }
}
