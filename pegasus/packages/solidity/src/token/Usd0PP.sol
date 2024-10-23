// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ICurvePool} from "shared/interfaces/curve/ICurvePool.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PausableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {ERC20PermitUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IUsd0PP} from "src/interfaces/token/IUsd0PP.sol";
import {IUsd0} from "./../interfaces/token/IUsd0.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";
import {IAirdropDistribution} from "src/interfaces/airdrop/IAirdropDistribution.sol";

import {
    CONTRACT_TREASURY,
    DEFAULT_ADMIN_ROLE,
    PEG_MAINTAINER_ROLE,
    EARLY_BOND_UNLOCK_ROLE,
    FLOOR_PRICE_UPDATER_ROLE,
    BOND_DURATION_FOUR_YEAR,
    END_OF_EARLY_UNLOCK_PERIOD,
    CURVE_POOL_USD0_USD0PP,
    CURVE_POOL_USD0_USD0PP_INTEGER_FOR_USD0,
    CURVE_POOL_USD0_USD0PP_INTEGER_FOR_USD0PP,
    PAUSING_CONTRACTS_ROLE,
    CONTRACT_AIRDROP_DISTRIBUTION,
    CONTRACT_AIRDROP_TAX_COLLECTOR,
    INITIAL_FLOOR_PRICE
} from "src/constants.sol";

import {
    BondNotStarted,
    BondFinished,
    BondNotFinished,
    OutsideEarlyUnlockTimeframe,
    NotAuthorized,
    AmountIsZero,
    Blacklisted,
    AmountTooBig,
    PARNotRequired,
    PARNotSuccessful,
    ApprovalFailed,
    PARUSD0InputExceedsBalance,
    NotPermittedToEarlyUnlock,
    InvalidInput,
    InvalidInputArraysLength,
    FloorPriceTooHigh,
    AmountMustBeGreaterThanZero,
    InsufficientUsd0ppBalance,
    FloorPriceNotSet,
    OutOfBounds
} from "src/errors.sol";

/// @title   Usd0PP Contract
/// @notice  Manages bond-like financial instruments for the UsualDAO ecosystem, providing functionality for minting, transferring, and unwrapping bonds.
/// @dev     Inherits from ERC20, ERC20PermitUpgradeable, and ReentrancyGuardUpgradeable to provide a range of functionalities along with protections against reentrancy attacks.
/// @dev     This contract is upgradeable, allowing for future improvements and enhancements.
/// @author  Usual Tech team

contract Usd0PP is
    IUsd0PP,
    ERC20PausableUpgradeable,
    ERC20PermitUpgradeable,
    ReentrancyGuardUpgradeable
{
    using CheckAccessControl for IRegistryAccess;
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:Usd0PP.storage.v0
    struct Usd0PPStorageV0 {
        /// The start time of the bond period.
        uint256 bondStart;
        /// The address of the registry contract.
        IRegistryContract registryContract;
        /// The address of the registry access contract.
        IRegistryAccess registryAccess;
        /// The USD0 token.
        IERC20 usd0;
        uint256 bondEarlyUnlockStart;
        uint256 bondEarlyUnlockEnd;
        mapping(address => uint256) bondEarlyUnlockAllowedAmount;
        mapping(address => bool) bondEarlyUnlockDisabled;
        /// The current floor price for unlocking USD0++ to USD0 (18 decimal places)
        uint256 floorPrice;
    }

    // keccak256(abi.encode(uint256(keccak256("Usd0PP.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant Usd0PPStorageV0Location =
        0x1519c21cc5b6e62f5c0018a7d32a0d00805e5b91f6eaa9f7bc303641242e3000;

    /// @notice Returns the storage struct of the contract.
    /// @return $ .
    function _usd0ppStorageV0() internal pure returns (Usd0PPStorageV0 storage $) {
        bytes32 position = Usd0PPStorageV0Location;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := position
        }
    }

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a bond is unwrapped.
    /// @param user The address of the user unwrapping the bond.
    /// @param amount The amount of the bond unwrapped.
    event BondUnwrapped(address indexed user, uint256 amount);

    /// @notice Emitted when a bond is unwrapped during the temporary unlock period.
    /// @param user The address of the user unwrapping the bond.
    /// @param amount The amount of the bond unwrapped.
    event BondUnwrappedDuringEarlyUnlock(address indexed user, uint256 amount);

    /// @notice Emitted when the PAR mechanism is triggered
    /// @param user The address of the caller triggering the mechanism
    /// @param amount The amount of USD0 supplied to the Curvepool to return to PAR.
    event PARMechanismActivated(address indexed user, uint256 amount);

    /// @notice Emitted when an emergency withdrawal occurs.
    /// @param account The address of the account initiating the emergency withdrawal.
    /// @param balance The balance withdrawn.
    event EmergencyWithdraw(address indexed account, uint256 balance);

    /// @notice Emitted when an address temporary redemption is disabled.
    /// @param user The address of the user being disabled for temporary redemptions.
    event BondEarlyUnlockDisabled(address indexed user);

    /// @notice Event emitted when the floor price is updated
    /// @param newFloorPrice The new floor price value
    event FloorPriceUpdated(uint256 newFloorPrice);

    /// @notice Event emitted when USD0++ is unlocked to USD0
    /// @param user The address of the user unlocking USD0++
    /// @param usd0ppAmount The amount of USD0++ unlocked
    /// @param usd0Amount The amount of USD0 received
    event Usd0ppUnlockedFloorPrice(address indexed user, uint256 usd0ppAmount, uint256 usd0Amount);

    /*//////////////////////////////////////////////////////////////
                             Constructor
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                             Initializer
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with floor price.
    /* cspell:disable-next-line */
    function initializeV1() public reinitializer(2) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        // Set initial floor price to INITIAL_FLOOR_PRICE
        if (INITIAL_FLOOR_PRICE == 0) {
            revert InvalidInput();
        }

        $.floorPrice = INITIAL_FLOOR_PRICE;
    }

    // @inheritdoc IUsd0PP
    function setupEarlyUnlockPeriod(uint256 bondEarlyUnlockStart, uint256 bondEarlyUnlockEnd)
        public
    {
        if (bondEarlyUnlockEnd > END_OF_EARLY_UNLOCK_PERIOD) {
            revert OutOfBounds();
        }
        if (bondEarlyUnlockStart >= bondEarlyUnlockEnd) {
            revert InvalidInput();
        }

        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(EARLY_BOND_UNLOCK_ROLE);
        $.bondEarlyUnlockStart = bondEarlyUnlockStart;
        $.bondEarlyUnlockEnd = bondEarlyUnlockEnd;
    }

    /*//////////////////////////////////////////////////////////////
                             External Functions
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc IUsd0PP
    function pause() public {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(PAUSING_CONTRACTS_ROLE);
        _pause();
    }

    // @inheritdoc IUsd0PP
    function unpause() external {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);
        _unpause();
    }

    // @inheritdoc IUsd0PP
    function mint(uint256 amountUsd0) public nonReentrant whenNotPaused {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        // revert if the bond period isn't started
        if (block.timestamp < $.bondStart) {
            revert BondNotStarted();
        }
        // revert if the bond period is finished
        if (block.timestamp >= $.bondStart + BOND_DURATION_FOUR_YEAR) {
            revert BondFinished();
        }

        // get the collateral token for the bond
        $.usd0.safeTransferFrom(msg.sender, address(this), amountUsd0);

        // mint the bond for the sender
        _mint(msg.sender, amountUsd0);
    }

    // @inheritdoc IUsd0PP
    function mintWithPermit(uint256 amountUsd0, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        try IERC20Permit(address($.usd0)).permit(
            msg.sender, address(this), amountUsd0, deadline, v, r, s
        ) {} catch {} // solhint-disable-line no-empty-blocks

        mint(amountUsd0);
    }

    // @inheritdoc IUsd0PP
    function unwrap() external nonReentrant whenNotPaused {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        // revert if the bond period is not finished
        if (block.timestamp < $.bondStart + BOND_DURATION_FOUR_YEAR) {
            revert BondNotFinished();
        }
        uint256 usd0PPBalance = balanceOf(msg.sender);

        _burn(msg.sender, usd0PPBalance);

        $.usd0.safeTransfer(msg.sender, usd0PPBalance);

        emit BondUnwrapped(msg.sender, usd0PPBalance);
    }

    // @inheritdoc IUsd0PP
    function temporaryOneToOneExitUnwrap(uint256 amountToUnwrap)
        external
        nonReentrant
        whenNotPaused
    {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        // revert if not during the temporary exit period
        if (block.timestamp < $.bondEarlyUnlockStart || block.timestamp > $.bondEarlyUnlockEnd) {
            revert OutsideEarlyUnlockTimeframe();
        }

        if ($.bondEarlyUnlockDisabled[msg.sender]) {
            revert NotAuthorized();
        }

        if (amountToUnwrap > $.bondEarlyUnlockAllowedAmount[msg.sender]) {
            revert NotPermittedToEarlyUnlock();
        }

        if (balanceOf(msg.sender) < amountToUnwrap) {
            revert AmountTooBig();
        }

        // this is a one-time option. It consumes the entire balance, even if only used partially.
        $.bondEarlyUnlockAllowedAmount[msg.sender] = 0;

        IAirdropDistribution airdropContract =
            IAirdropDistribution($.registryContract.getContract(CONTRACT_AIRDROP_DISTRIBUTION));

        airdropContract.voidAnyOutstandingAirdrop(msg.sender);

        _burn(msg.sender, amountToUnwrap);

        $.usd0.safeTransfer(msg.sender, amountToUnwrap);

        emit BondUnwrappedDuringEarlyUnlock(msg.sender, amountToUnwrap);
    }

    // @inheritdoc IUsd0PP
    function allocateEarlyUnlockBalance(
        address[] calldata addressesToAllocateTo,
        uint256[] calldata balancesToAllocate
    ) external nonReentrant whenNotPaused {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        $.registryAccess.onlyMatchingRole(EARLY_BOND_UNLOCK_ROLE);

        if (addressesToAllocateTo.length != balancesToAllocate.length) {
            revert InvalidInputArraysLength();
        }

        for (uint256 i; i < addressesToAllocateTo.length;) {
            $.bondEarlyUnlockAllowedAmount[addressesToAllocateTo[i]] = balancesToAllocate[i];

            unchecked {
                ++i;
            }
        }
    }

    function unwrapPegMaintainer(uint256 amount) external nonReentrant whenNotPaused {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        $.registryAccess.onlyMatchingRole(PEG_MAINTAINER_ROLE);
        // revert if the bond period has not started
        if (block.timestamp < $.bondStart) {
            revert BondNotStarted();
        }
        uint256 usd0PPBalance = balanceOf(msg.sender);
        if (usd0PPBalance < amount) {
            revert AmountTooBig();
        }
        _burn(msg.sender, amount);

        $.usd0.safeTransfer(msg.sender, amount);

        emit BondUnwrapped(msg.sender, amount);
    }

    // @inheritdoc IUsd0PP
    function triggerPARMechanismCurvepool(
        uint256 parUsd0Amount,
        uint256 minimumPARMechanismGainedAmount
    ) external nonReentrant whenNotPaused {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        $.registryAccess.onlyMatchingRole(PEG_MAINTAINER_ROLE);
        // revert if the bond period has not started
        if (block.timestamp < $.bondStart) {
            revert BondNotStarted();
        }
        if (parUsd0Amount == 0 || minimumPARMechanismGainedAmount == 0) {
            revert AmountIsZero();
        }
        IERC20 usd0 = $.usd0;

        uint256 usd0BalanceBeforePAR = usd0.balanceOf(address(this));
        uint256 usd0ppBalanceBeforePAR = balanceOf(address(this));
        if (usd0BalanceBeforePAR < parUsd0Amount) {
            revert PARUSD0InputExceedsBalance();
        }

        ICurvePool curvepool = ICurvePool(address(CURVE_POOL_USD0_USD0PP));
        //@notice, deposit USD0 into curvepool to receive USD0++
        if (!(usd0.approve(address(curvepool), parUsd0Amount))) {
            revert ApprovalFailed();
        }

        uint256 receivedUsd0pp = curvepool.exchange(
            CURVE_POOL_USD0_USD0PP_INTEGER_FOR_USD0,
            CURVE_POOL_USD0_USD0PP_INTEGER_FOR_USD0PP,
            parUsd0Amount,
            parUsd0Amount + minimumPARMechanismGainedAmount,
            address(this)
        );
        if (receivedUsd0pp < parUsd0Amount) {
            revert PARNotRequired();
        }

        uint256 usd0ppBalanceChangeAfterPAR = balanceOf(address(this)) - usd0ppBalanceBeforePAR;

        _burn(address(this), usd0ppBalanceChangeAfterPAR);
        emit BondUnwrapped(address(this), usd0ppBalanceChangeAfterPAR);

        uint256 gainedUSD0AmountPAR = usd0ppBalanceChangeAfterPAR - parUsd0Amount;

        usd0.safeTransfer($.registryContract.getContract(CONTRACT_TREASURY), gainedUSD0AmountPAR);

        if (usd0.balanceOf(address(this)) < totalSupply()) {
            revert PARNotSuccessful();
        }

        emit PARMechanismActivated(msg.sender, gainedUSD0AmountPAR);
    }

    /// @notice function for executing the emergency withdrawal of Usd0.
    /// @param  safeAccount The address of the account to withdraw the Usd0 to.
    /// @dev    Reverts if the caller does not have the DEFAULT_ADMIN_ROLE role.
    function emergencyWithdraw(address safeAccount) external {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        if (!$.registryAccess.hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAuthorized();
        }
        IERC20 usd0 = $.usd0;

        uint256 balance = usd0.balanceOf(address(this));
        // get the collateral token for the bond
        usd0.safeTransfer(safeAccount, balance);

        // Pause the contract
        _pause();

        emit EmergencyWithdraw(safeAccount, balance);
    }

    // @inheritdoc IUsd0PP
    function updateFloorPrice(uint256 newFloorPrice) external {
        if (newFloorPrice > 1e18) {
            revert FloorPriceTooHigh();
        }
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.registryAccess.onlyMatchingRole(FLOOR_PRICE_UPDATER_ROLE);

        $.floorPrice = newFloorPrice;

        emit FloorPriceUpdated(newFloorPrice);
    }

    // @inheritdoc IUsd0PP
    function unlockUsd0ppFloorPrice(uint256 usd0ppAmount) external nonReentrant whenNotPaused {
        if (usd0ppAmount == 0) {
            revert AmountMustBeGreaterThanZero();
        }
        if (balanceOf(msg.sender) < usd0ppAmount) {
            revert InsufficientUsd0ppBalance();
        }
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        if ($.floorPrice == 0) {
            revert FloorPriceNotSet();
        }

        // as floorPrice can't be greater than 1e18, we will never have a usd0Amount greater than the usd0 backing
        uint256 usd0Amount = Math.mulDiv(usd0ppAmount, $.floorPrice, 1e18, Math.Rounding.Floor);

        _burn(msg.sender, usd0ppAmount);
        $.usd0.safeTransfer(msg.sender, usd0Amount);

        // Calculate and transfer the delta to the treasury
        uint256 delta = usd0ppAmount - usd0Amount;
        if (delta > 0) {
            address treasury = $.registryContract.getContract(CONTRACT_TREASURY);
            $.usd0.safeTransfer(treasury, delta);
        }

        emit Usd0ppUnlockedFloorPrice(msg.sender, usd0ppAmount, usd0Amount);
    }

    // @inheritdoc IUsd0PP
    function setBondEarlyUnlockDisabled(address user) external whenNotPaused {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();

        if (msg.sender != $.registryContract.getContract(CONTRACT_AIRDROP_TAX_COLLECTOR)) {
            revert NotAuthorized();
        }
        $.bondEarlyUnlockDisabled[user] = true;
        emit BondEarlyUnlockDisabled(user);
    }

    /*//////////////////////////////////////////////////////////////
                             View Functions
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc IUsd0PP
    function totalBondTimes() public pure returns (uint256) {
        return BOND_DURATION_FOUR_YEAR;
    }

    // @inheritdoc IUsd0PP
    function getBondEarlyUnlockDisabled(address user) external view returns (bool) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.bondEarlyUnlockDisabled[user];
    }

    // @inheritdoc IUsd0PP
    function getStartTime() external view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.bondStart;
    }

    // @inheritdoc IUsd0PP
    function getEndTime() external view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.bondStart + BOND_DURATION_FOUR_YEAR;
    }

    // @inheritdoc IUsd0PP
    function getFloorPrice() external view returns (uint256) {
        return _usd0ppStorageV0().floorPrice;
    }

    // @inheritdoc IUsd0PP
    function getTemporaryUnlockStartTime() external view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.bondEarlyUnlockStart;
    }

    // @inheritdoc IUsd0PP
    function getTemporaryUnlockEndTime() external view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.bondEarlyUnlockEnd;
    }

    // @inheritdoc IUsd0PP
    function getAllocationEarlyUnlock(address addressToCheck) external view returns (uint256) {
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        return $.bondEarlyUnlockAllowedAmount[addressToCheck];
    }

    /*//////////////////////////////////////////////////////////////
                             Internal Functions
    //////////////////////////////////////////////////////////////*/

    function _update(address sender, address recipient, uint256 amount)
        internal
        override(ERC20PausableUpgradeable, ERC20Upgradeable)
    {
        if (amount == 0) {
            revert AmountIsZero();
        }
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        IUsd0 usd0 = IUsd0(address($.usd0));
        if (usd0.isBlacklisted(sender) || usd0.isBlacklisted(recipient)) {
            revert Blacklisted();
        }
        // we update the balance of the sender and the recipient
        super._update(sender, recipient, amount);
    }
}
