// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IAirdropDistribution} from "src/interfaces/airdrop/IAirdropDistribution.sol";
import {IAirdropTaxCollector} from "src/interfaces/airdrop/IAirdropTaxCollector.sol";
import {IUsual} from "src/interfaces/token/IUsual.sol";
import {MerkleProof} from "openzeppelin-contracts/utils/cryptography/MerkleProof.sol";

import {
    CONTRACT_USUAL,
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_AIRDROP_TAX_COLLECTOR,
    AIRDROP_VESTING_DURATION_IN_MONTHS,
    END_OF_EARLY_UNLOCK_PERIOD,
    AIRDROP_INITIAL_START_TIME,
    FIRST_AIRDROP_VESTING_CLAIMING_DATE,
    SECOND_AIRDROP_VESTING_CLAIMING_DATE,
    THIRD_AIRDROP_VESTING_CLAIMING_DATE,
    FOURTH_AIRDROP_VESTING_CLAIMING_DATE,
    FIFTH_AIRDROP_VESTING_CLAIMING_DATE,
    SIXTH_AIRDROP_VESTING_CLAIMING_DATE,
    BASIS_POINT_BASE,
    DEFAULT_ADMIN_ROLE,
    AIRDROP_OPERATOR_ROLE,
    AIRDROP_PENALTY_OPERATOR_ROLE,
    PAUSING_CONTRACTS_ROLE,
    CONTRACT_USD0PP
} from "src/constants.sol";
import {
    NullContract,
    NullMerkleRoot,
    InvalidProof,
    AmountTooBig,
    AmountIsZero,
    NotClaimableYet,
    NothingToClaim,
    SameValue,
    NullAddress,
    OutOfBounds,
    InvalidInputArraysLength,
    InvalidClaimingPeriodStartDate,
    AirdropVoided,
    NotAuthorized
} from "src/errors.sol";

/// @title   Airdrop Distribution contract
/// @notice  Manages the Airdrop Distribution
/// @author  Usual Tech team
contract AirdropDistribution is
    Initializable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IAirdropDistribution
{
    using Math for uint256;
    using CheckAccessControl for IRegistryAccess;

    /// @custom:storage-location erc7201:AirdropDistribution.storage.v0
    struct AirdropDistributionStorageV0 {
        // The registry access contract
        IRegistryAccess registryAccess;
        // The registry contract
        IRegistryContract registryContract;
        // The airdrop tax collector contract
        IAirdropTaxCollector airdropTaxCollector;
        // The usual token contract
        IUsual usualToken;
        // The merkle root of the distribution
        bytes32 merkleRoot;
        // The claimed amount for each account
        mapping(address => uint256) claimed;
        // The penalty percentage for each account for each month
        mapping(address => mapping(uint256 => uint256)) penaltyPercentageByMonth;
        // Whether the ragequit has been used, voiding any airdrop
        mapping(address => bool) ragequit;
    }

    // keccak256(abi.encode(uint256(keccak256("AirdropDistribution.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant AirdropDistributionStorageV0Location =
        0x8c5333b52aa1c4b5abeff2afd2c59c576cb9feb83f66f959574b22a3a8f8cf00;

    /// @notice Returns the storage struct of the contract.
    /// @return $ .
    function _airdropDistributionStorageV0()
        internal
        pure
        returns (AirdropDistributionStorageV0 storage $)
    {
        bytes32 position = AirdropDistributionStorageV0Location;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := position
        }
    }

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the merkle root is set
    /// @param merkleRoot The merkle root set
    event MerkleRootSet(bytes32 indexed merkleRoot);

    /// @notice Emitted when the penalty percentages are set
    /// @param accounts The accounts set
    /// @param penaltyPercentages The penalty percentages set
    /// @param month The month set
    event PenaltyPercentagesSet(
        address[] indexed accounts, uint256[] indexed penaltyPercentages, uint256 indexed month
    );

    /// @notice Emitted when a claim is made
    /// @param account The account that made the claim
    /// @param amount The amount claimed
    event Claimed(address indexed account, uint256 indexed amount);

    /// @notice Emitted when an account ragequits the airdrop
    /// @param account The account that ragequitted the airdrop
    event Ragequit(address indexed account);

    /*///////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                             Initializer
    //////////////////////////////////////////////////////////////*/

    /// @notice  Initializes the contract with a registry contract.
    /// @param   _registryContract Address of the registry contract for role management.
    function initialize(address _registryContract) public initializer {
        if (_registryContract == address(0)) {
            revert NullContract();
        }

        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();

        AirdropDistributionStorageV0 storage $ = _airdropDistributionStorageV0();
        $.registryContract = IRegistryContract(_registryContract);
        $.registryAccess = IRegistryAccess($.registryContract.getContract(CONTRACT_REGISTRY_ACCESS));
        $.usualToken = IUsual($.registryContract.getContract(CONTRACT_USUAL));
        $.airdropTaxCollector =
            IAirdropTaxCollector($.registryContract.getContract(CONTRACT_AIRDROP_TAX_COLLECTOR));

        // Check if the start time is within the correct range
        if (AIRDROP_INITIAL_START_TIME >= FIRST_AIRDROP_VESTING_CLAIMING_DATE) {
            revert InvalidClaimingPeriodStartDate();
        }
        // Sanity check of vesting constants
        if (
            !(
                END_OF_EARLY_UNLOCK_PERIOD < FIRST_AIRDROP_VESTING_CLAIMING_DATE
                    && FIRST_AIRDROP_VESTING_CLAIMING_DATE < SECOND_AIRDROP_VESTING_CLAIMING_DATE
                    && SECOND_AIRDROP_VESTING_CLAIMING_DATE < THIRD_AIRDROP_VESTING_CLAIMING_DATE
                    && THIRD_AIRDROP_VESTING_CLAIMING_DATE < FOURTH_AIRDROP_VESTING_CLAIMING_DATE
                    && FOURTH_AIRDROP_VESTING_CLAIMING_DATE < FIFTH_AIRDROP_VESTING_CLAIMING_DATE
                    && FIFTH_AIRDROP_VESTING_CLAIMING_DATE < SIXTH_AIRDROP_VESTING_CLAIMING_DATE
            )
        ) {
            revert OutOfBounds();
        }
    }

    /*//////////////////////////////////////////////////////////////
                               Internal
    //////////////////////////////////////////////////////////////*/

    /// @notice Computes the penalty amount for the given account.
    /// @param $ The storage struct of the contract.
    /// @param totalAmount Total amount claimable by the user.
    /// @param account Address of the account.
    /// @param monthsPassed Number of months passed since the start of the vesting period.
    /// @return The penalty amount.
    function _computePenalty(
        AirdropDistributionStorageV0 storage $,
        uint256 totalAmount,
        address account,
        uint256 monthsPassed
    ) internal returns (uint256) {
        uint256 penaltyAmount = 0;
        uint256 oneSixthAmount =
            totalAmount.mulDiv(1, AIRDROP_VESTING_DURATION_IN_MONTHS, Math.Rounding.Ceil);

        for (uint256 i = 1; i <= monthsPassed; i++) {
            if ($.penaltyPercentageByMonth[account][i] == 0) {
                continue;
            } else if ($.penaltyPercentageByMonth[account][i] == BASIS_POINT_BASE) {
                penaltyAmount += oneSixthAmount;
            } else {
                uint256 monthlyPenalty =
                    oneSixthAmount.mulDiv($.penaltyPercentageByMonth[account][i], BASIS_POINT_BASE);
                penaltyAmount += monthlyPenalty;
            }
            $.penaltyPercentageByMonth[account][i] = 0;
        }
        return penaltyAmount;
    }

    /// @notice Checks how much a user can claim.
    /// @param $ The storage struct of the contract.
    /// @param account Address of the account.
    /// @param totalAmount Total amount claimable by the user.
    /// @param isTop80 Whether the account is in the top 80% of the distribution (only used for vesting).
    /// @return The amount available to claim.
    /// @return The penalty amount.
    function _available(
        AirdropDistributionStorageV0 storage $,
        address account,
        uint256 totalAmount,
        bool isTop80
    ) internal returns (uint256, uint256) {
        if (block.timestamp < AIRDROP_INITIAL_START_TIME) {
            revert NotClaimableYet();
        }

        uint256 claimableAmount = totalAmount;
        uint256 monthsPassed = _calculateMonthsPassed();
        uint256 totalClaimed = $.claimed[account];
        uint256 penaltyAmount = 0;
        bool hasPaidTax = $.airdropTaxCollector.hasPaidTax(account);

        if (isTop80 && !hasPaidTax) {
            // slither-disable-next-line incorrect-equality
            if (monthsPassed == 0) {
                revert NotClaimableYet();
            }
            claimableAmount = totalAmount.mulDiv(monthsPassed, AIRDROP_VESTING_DURATION_IN_MONTHS);
        }

        // Penalty is computed only if the account is in the top 80%
        if (isTop80) {
            penaltyAmount = _computePenalty(
                $, totalAmount, account, hasPaidTax ? monthsPassed + 1 : monthsPassed
            );
        }

        // Subtract penalties from the claimable amount
        if (penaltyAmount > claimableAmount) {
            penaltyAmount = claimableAmount;
        }

        claimableAmount -= penaltyAmount;

        if (claimableAmount <= totalClaimed) {
            revert NothingToClaim();
        }

        return (claimableAmount - totalClaimed, penaltyAmount);
    }

    function _calculateMonthsPassed() internal view returns (uint256) {
        uint256[6] memory airdropClaimingDates = [
            FIRST_AIRDROP_VESTING_CLAIMING_DATE,
            SECOND_AIRDROP_VESTING_CLAIMING_DATE,
            THIRD_AIRDROP_VESTING_CLAIMING_DATE,
            FOURTH_AIRDROP_VESTING_CLAIMING_DATE,
            FIFTH_AIRDROP_VESTING_CLAIMING_DATE,
            SIXTH_AIRDROP_VESTING_CLAIMING_DATE
        ];

        uint256 monthsPassed = 0;
        for (uint256 i = 0; i < airdropClaimingDates.length;) {
            if (block.timestamp < airdropClaimingDates[i]) {
                return monthsPassed;
            }
            monthsPassed++;

            unchecked {
                ++i;
            }
        }
        return monthsPassed;
    }

    /// @notice Verify the merkle proof for the given account.
    /// @param $ The storage struct of the contract.
    /// @param account Address of the account.
    /// @param isTop80 Whether the account is in the top 80% of the distribution.
    /// @param totalAmount Total amount claimable by the user.
    /// @param proof Merkle proof.
    /// @return True if the proof is valid, false otherwise.
    function _verifyMerkleProof(
        AirdropDistributionStorageV0 storage $,
        address account,
        bool isTop80,
        uint256 totalAmount,
        bytes32[] calldata proof
    ) internal view returns (bool) {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(account, totalAmount, isTop80))));
        return MerkleProof.verify(proof, $.merkleRoot, leaf);
    }

    /*//////////////////////////////////////////////////////////////
                               External
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc IAirdropDistribution
    function claim(address account, bool isTop80, uint256 amount, bytes32[] calldata proof)
        external
        whenNotPaused
        nonReentrant
    {
        if (account == address(0)) {
            revert NullAddress();
        }
        if (amount == 0) {
            revert AmountIsZero();
        }

        AirdropDistributionStorageV0 storage $ = _airdropDistributionStorageV0();

        if (!_verifyMerkleProof($, account, isTop80, amount, proof)) {
            revert InvalidProof();
        }

        if ($.ragequit[account]) {
            revert AirdropVoided();
        }

        (uint256 amountToClaim, uint256 penaltyAmount) = _available($, account, amount, isTop80);

        $.claimed[account] += amountToClaim + penaltyAmount;
        $.usualToken.mint(account, amountToClaim);
        emit Claimed(account, amountToClaim);
    }

    /*//////////////////////////////////////////////////////////////
                          Restricted functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the merkle root for the distribution module.
    /// @param _merkleRoot The merkle root.
    function setMerkleRoot(bytes32 _merkleRoot) external {
        if (_merkleRoot == bytes32(0)) {
            revert NullMerkleRoot();
        }
        AirdropDistributionStorageV0 storage $ = _airdropDistributionStorageV0();
        $.registryAccess.onlyMatchingRole(AIRDROP_OPERATOR_ROLE);
        $.merkleRoot = _merkleRoot;
        emit MerkleRootSet(_merkleRoot);
    }

    /// @notice Sets the penalty percentages for multiple accounts for a given month.
    /// @param penaltyPercentages Array of penalty percentages in basis points.
    /// @param accounts Array of addresses of the accounts.
    /// @param month The month of the vesting period.
    function setPenaltyPercentages(
        uint256[] memory penaltyPercentages,
        address[] memory accounts,
        uint256 month
    ) external {
        uint256 monthsPassed = _calculateMonthsPassed();

        // Validate the month is within the 6-month vesting period
        if (month < monthsPassed || month > AIRDROP_VESTING_DURATION_IN_MONTHS) {
            revert OutOfBounds();
        }

        // Validate the length of the arrays
        if (penaltyPercentages.length != accounts.length) {
            revert InvalidInputArraysLength();
        }

        AirdropDistributionStorageV0 storage $ = _airdropDistributionStorageV0();
        $.registryAccess.onlyMatchingRole(AIRDROP_PENALTY_OPERATOR_ROLE);

        for (uint256 i = 0; i < accounts.length; i++) {
            if (penaltyPercentages[i] > BASIS_POINT_BASE) {
                revert AmountTooBig();
            }
            if (penaltyPercentages[i] == $.penaltyPercentageByMonth[accounts[i]][month]) {
                revert SameValue();
            }
            $.penaltyPercentageByMonth[accounts[i]][month] = penaltyPercentages[i];
        }

        emit PenaltyPercentagesSet(accounts, penaltyPercentages, month);
    }

    /// @notice Pauses the claim contract function
    /// @dev Can only be called by the PAUSING_CONTRACTS_ROLE.
    function pause() external {
        AirdropDistributionStorageV0 storage $ = _airdropDistributionStorageV0();
        $.registryAccess.onlyMatchingRole(PAUSING_CONTRACTS_ROLE);
        _pause();
    }

    /// @notice Unpauses the claim contract function
    /// @dev Can only be called by the admin.
    function unpause() external {
        AirdropDistributionStorageV0 storage $ = _airdropDistributionStorageV0();
        $.registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);
        _unpause();
    }

    // @inheritdoc IAirdropDistribution
    function voidAnyOutstandingAirdrop(address account) external {
        AirdropDistributionStorageV0 storage $ = _airdropDistributionStorageV0();
        // Verify that calling contract is the USD0PP contract
        if (msg.sender != $.registryContract.getContract(CONTRACT_USD0PP)) {
            revert NotAuthorized();
        }
        if ($.ragequit[account]) {
            revert AirdropVoided();
        }
        $.ragequit[account] = true;
        emit Ragequit(account);
    }

    /*//////////////////////////////////////////////////////////////
                               Getters
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the merkle root.
    /// @return The merkle root.
    function getMerkleRoot() external view returns (bytes32) {
        AirdropDistributionStorageV0 storage $ = _airdropDistributionStorageV0();
        return $.merkleRoot;
    }

    /// @notice Returns the penalty percentage for the given account.
    /// @param account Address of the account.
    /// @param month The month of the vesting period.
    /// @return The penalty percentage in basis points for the given account and month.
    function getPenaltyPercentage(address account, uint256 month) external view returns (uint256) {
        AirdropDistributionStorageV0 storage $ = _airdropDistributionStorageV0();
        return $.penaltyPercentageByMonth[account][month];
    }

    /// @notice Returns the vesting duration of the distribution.
    /// @return The vesting duration.
    function getVestingDuration() external pure returns (uint256) {
        return SIXTH_AIRDROP_VESTING_CLAIMING_DATE - AIRDROP_INITIAL_START_TIME;
    }

    /// @notice Returns the claimed amount for the given account.
    /// @param account Address of the account.
    /// @return The claimed amount.
    function getClaimed(address account) external view returns (uint256) {
        AirdropDistributionStorageV0 storage $ = _airdropDistributionStorageV0();
        return $.claimed[account];
    }

    // @inheritdoc IAirdropDistribution
    function getRagequitStatus(address account) external view returns (bool) {
        AirdropDistributionStorageV0 storage $ = _airdropDistributionStorageV0();
        return $.ragequit[account];
    }
}
