// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";

import {IUsualS} from "src/interfaces/token/IUsualS.sol";
import {IUsualSP} from "src/interfaces/token/IUsualSP.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";

import {RewardAccrualBase} from "src/modules/RewardAccrualBase.sol";

import {
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_USUALS,
    CONTRACT_USUAL,
    CONTRACT_DISTRIBUTION_MODULE,
    DEFAULT_ADMIN_ROLE,
    USUALSP_OPERATOR_ROLE,
    PAUSING_CONTRACTS_ROLE,
    ONE_MONTH,
    NUMBER_OF_MONTHS_IN_THREE_YEARS
} from "src/constants.sol";
import {
    NullContract,
    CliffBiggerThanDuration,
    InvalidInputArraysLength,
    StartTimeInPast,
    NotAuthorized,
    NotClaimableYet,
    AlreadyClaimed,
    AmountIsZero,
    InsufficientUsualSLiquidAllocation,
    InvalidInput,
    CannotReduceAllocation
} from "src/errors.sol";

/// @title   UsualSP contract
/// @notice  Stacked vesting contract for USUALS tokens.
/// @dev     The contract allows insiders to claim their USUALSP tokens over a vesting period. It also allows users to stake their USUALS tokens to receive yield.
/// @author  Usual Tech team
contract UsualSP is RewardAccrualBase, PausableUpgradeable, ReentrancyGuardUpgradeable, IUsualSP {
    using CheckAccessControl for IRegistryAccess;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @custom:storage-location erc7201:UsualSP.storage.v0
    struct UsualSPStorageV0 {
        /// The RegistryContract instance for contract interactions.
        IRegistryContract registryContract;
        /// The RegistryAccess contract instance for role checks.
        IRegistryAccess registryAccess;
        /// The USUALS token.
        IERC20 usualS;
        /// The USUAL token.
        IERC20 usual;
        /// The start date of the vesting period.
        uint256 startDate;
        /// The duration of the vesting period.
        uint256 duration;
        /// Mapping of insiders and their cliff duration.
        mapping(address => uint256) cliffDuration;
        /// Mapping of insiders and their original allocation.
        mapping(address => uint256) originalAllocation;
        /// Mapping of users and their liquid allocation.
        mapping(address => uint256) liquidAllocation;
        /// Mapping of insiders and their already claimed original allocation.
        mapping(address => uint256) originalClaimed;
    }

    // keccak256(abi.encode(uint256(keccak256("UsualSP.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant UsualSPStorageV0Location =
        0xc4eb842bdb0bb6ace39c07132f299ffcb0c8b757dc80b8ab97ab5f4422bed900;

    /// @notice Returns the storage struct of the contract.
    /// @return $ .
    function _usualSPStorageV0() internal pure returns (UsualSPStorageV0 storage $) {
        bytes32 position = UsualSPStorageV0Location;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := position
        }
    }

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an insider claims their original allocation.
    /// @param account The address of the insider.
    /// @param amount The amount of tokens claimed.
    event ClaimedOriginalAllocation(address indexed account, uint256 amount);

    /// @notice Emitted when an allocation is removed
    /// @param account The address of the account whose allocation was removed
    event RemovedOriginalAllocation(address indexed account);

    /// @notice Emitted when a new allocation is set.
    /// @param recipients The addresses of the recipients.
    /// @param allocations The allocations of the recipients.
    /// @param cliffDurations The cliff durations of the recipients.
    event NewAllocation(address[] recipients, uint256[] allocations, uint256[] cliffDurations);

    /// @notice Emitted when the stake is made
    /// @param account The address of the user.
    /// @param amount The amount of tokens staked.
    event Stake(address account, uint256 amount);

    /// @notice Emitted when the unstake is made
    /// @param account The address of the user.
    /// @param amount The amount of tokens unstaked.
    event Unstake(address account, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                             Constructor
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                             INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice  Initializes the contract with a registry contract, start date and duration.
    /// @param _registryContract Address of the registry contract for role management.
    /// @param _startDate The start time of the vesting period.
    /// @param _duration The duration of the vesting period.
    function initialize(address _registryContract, uint256 _startDate, uint256 _duration)
        public
        initializer
    {
        _createUsualSPCheck(_registryContract, _startDate, _duration);

        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();

        UsualSPStorageV0 storage $ = _usualSPStorageV0();
        $.registryContract = IRegistryContract(_registryContract);
        $.registryAccess = IRegistryAccess($.registryContract.getContract(CONTRACT_REGISTRY_ACCESS));
        $.usualS = IERC20($.registryContract.getContract(CONTRACT_USUALS));
        $.usual = IERC20($.registryContract.getContract(CONTRACT_USUAL));
        $.startDate = _startDate;
        $.duration = _duration;

        __RewardAccrualBase_init_unchained(address($.usual));
    }

    /*//////////////////////////////////////////////////////////////
                              Internal
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks the validity of parameters needed for creating a new USUALSP contract.
    /// @param registryContract_  The address of the RegistryContract.
    /// @param startTime_  The start time of the vesting period.
    /// @param duration_ The duration of the vesting period.
    function _createUsualSPCheck(address registryContract_, uint256 startTime_, uint256 duration_)
        internal
        view
    {
        if (registryContract_ == address(0)) {
            revert NullContract();
        }
        if (startTime_ < block.timestamp) {
            revert StartTimeInPast();
        }
        if (duration_ == 0) {
            revert AmountIsZero();
        }
    }

    /// @notice Check how much an insider can claim.
    /// @param $ The storage struct of the contract.
    /// @param insider The address of the insider.
    /// @return The total amount available to claim.
    function _released(UsualSPStorageV0 storage $, address insider)
        internal
        view
        returns (uint256)
    {
        uint256 insiderCliffDuration = $.cliffDuration[insider];

        uint256 totalMonthsInCliffDuration = insiderCliffDuration / ONE_MONTH;
        uint256 totalAllocation = $.originalAllocation[insider];

        if (block.timestamp < $.startDate + insiderCliffDuration) {
            // No tokens can be claimed before the cliff duration
            revert NotClaimableYet();
        } else if (block.timestamp >= $.startDate + $.duration) {
            // All tokens can be claimed after the duration
            return totalAllocation;
        } else {
            // Calculate the number of months passed since the cliff duration
            uint256 monthsPassed =
                (block.timestamp - $.startDate - insiderCliffDuration) / ONE_MONTH;

            // Calculate the vested amount based on the number of months passed
            uint256 vestedAmount = totalAllocation.mulDiv(
                totalMonthsInCliffDuration + monthsPassed,
                NUMBER_OF_MONTHS_IN_THREE_YEARS,
                Math.Rounding.Floor
            );

            // Ensure we don't release more than the total allocation due to rounding
            return Math.min(vestedAmount, totalAllocation);
        }
    }

    /// @notice Check how much an insider can claim.
    /// @param $ The storage struct of the contract.
    /// @param insider The address of the insider.
    /// @return The total amount available to claim minus the already claimed amount.
    function _available(UsualSPStorageV0 storage $, address insider)
        internal
        view
        returns (uint256)
    {
        return _released($, insider) - $.originalClaimed[insider];
    }

    /*//////////////////////////////////////////////////////////////
                               External
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUsualSP
    function claimOriginalAllocation() external nonReentrant whenNotPaused {
        UsualSPStorageV0 storage $ = _usualSPStorageV0();

        if ($.originalAllocation[msg.sender] == 0) {
            revert NotAuthorized();
        }

        _updateReward(msg.sender);

        uint256 amount = _available($, msg.sender);
        // slither-disable-next-line incorrect-equality
        if (amount == 0) {
            revert AlreadyClaimed();
        }
        $.originalClaimed[msg.sender] += amount;
        $.usualS.safeTransfer(msg.sender, amount);

        emit ClaimedOriginalAllocation(msg.sender, amount);
    }

    /// @inheritdoc IUsualSP
    function stake(uint256 amount) public nonReentrant whenNotPaused {
        if (amount == 0) {
            revert AmountIsZero();
        }

        _updateReward(msg.sender);

        UsualSPStorageV0 storage $ = _usualSPStorageV0();

        // Transfer the UsualS tokens from the user to the contract
        $.usualS.safeTransferFrom(msg.sender, address(this), amount);

        // Update the liquid allocation
        $.liquidAllocation[msg.sender] += amount;

        emit Stake(msg.sender, amount);
    }

    /// @inheritdoc IUsualSP
    function stakeWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        UsualSPStorageV0 storage $ = _usualSPStorageV0();

        try IERC20Permit(address($.usualS)).permit(
            msg.sender, address(this), amount, deadline, v, r, s
        ) {} catch {} // solhint-disable-line no-empty-blocks

        stake(amount);
    }

    /// @inheritdoc IUsualSP
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) {
            revert AmountIsZero();
        }

        _updateReward(msg.sender);

        UsualSPStorageV0 storage $ = _usualSPStorageV0();

        if ($.liquidAllocation[msg.sender] < amount) {
            revert InsufficientUsualSLiquidAllocation();
        }

        $.liquidAllocation[msg.sender] -= amount;
        $.usualS.safeTransfer(msg.sender, amount);

        emit Unstake(msg.sender, amount);
    }

    /// @inheritdoc IUsualSP
    function claimReward() external nonReentrant whenNotPaused returns (uint256) {
        UsualSPStorageV0 storage $ = _usualSPStorageV0();

        if (block.timestamp < $.startDate + ONE_MONTH) {
            revert NotClaimableYet();
        }

        return _claimRewards();
    }

    /*//////////////////////////////////////////////////////////////
                         Restricted functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUsualSP
    function allocate(
        address[] calldata recipients,
        uint256[] calldata originalAllocations,
        uint256[] calldata cliffDurations
    ) external {
        UsualSPStorageV0 storage $ = _usualSPStorageV0();
        $.registryAccess.onlyMatchingRole(USUALSP_OPERATOR_ROLE);

        if (
            recipients.length != originalAllocations.length
                || recipients.length != cliffDurations.length || recipients.length == 0
        ) {
            revert InvalidInputArraysLength();
        }

        for (uint256 i; i < recipients.length;) {
            if (cliffDurations[i] > $.duration) {
                revert CliffBiggerThanDuration();
            }
            if (recipients[i] == address(0)) {
                revert InvalidInput();
            }

            if (originalAllocations[i] < $.originalAllocation[recipients[i]]) {
                revert CannotReduceAllocation();
            }

            _updateReward(recipients[i]);

            $.originalAllocation[recipients[i]] = originalAllocations[i];
            $.cliffDuration[recipients[i]] = cliffDurations[i];

            unchecked {
                ++i;
            }
        }
        emit NewAllocation(recipients, originalAllocations, cliffDurations);
    }

    /// @inheritdoc IUsualSP
    function removeOriginalAllocation(address[] calldata recipients) external {
        if (recipients.length == 0) {
            revert InvalidInputArraysLength();
        }

        UsualSPStorageV0 storage $ = _usualSPStorageV0();
        $.registryAccess.onlyMatchingRole(USUALSP_OPERATOR_ROLE);

        for (uint256 i; i < recipients.length;) {
            $.originalAllocation[recipients[i]] = 0;
            $.originalClaimed[recipients[i]] = 0;

            emit RemovedOriginalAllocation(recipients[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Pauses the contract, preventing claiming.
    /// @dev Can only be called by the pauser.
    function pause() external {
        UsualSPStorageV0 storage $ = _usualSPStorageV0();
        $.registryAccess.onlyMatchingRole(PAUSING_CONTRACTS_ROLE);
        _pause();
    }

    /// @notice Unpauses the contract, allowing claiming.
    /// @dev Can only be called by the admin.
    function unpause() external {
        UsualSPStorageV0 storage $ = _usualSPStorageV0();
        $.registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);
        _unpause();
    }

    /// @inheritdoc IUsualSP
    function stakeUsualS() external {
        UsualSPStorageV0 storage $ = _usualSPStorageV0();
        $.registryAccess.onlyMatchingRole(USUALSP_OPERATOR_ROLE);
        IUsualS(address($.usualS)).stakeAll();
    }

    /// @inheritdoc IUsualSP
    function startRewardDistribution(uint256 amount, uint256 startTime, uint256 endTime) external {
        UsualSPStorageV0 storage $ = _usualSPStorageV0();

        address distributionModule = $.registryContract.getContract(CONTRACT_DISTRIBUTION_MODULE);
        if (msg.sender != distributionModule) {
            revert NotAuthorized();
        }

        _startRewardDistribution(amount, startTime, endTime);
    }

    /*//////////////////////////////////////////////////////////////
                               Getters
    //////////////////////////////////////////////////////////////*/

    /// @notice  Returns the vesting start date.
    /// @return  The start date.
    function getStartDate() external view returns (uint256) {
        UsualSPStorageV0 storage $ = _usualSPStorageV0();
        return $.startDate;
    }

    /// @notice Returns the liquid allocation of an account.
    /// @param account The address of the account.
    /// @return The liquid allocation.
    function getLiquidAllocation(address account) external view returns (uint256) {
        UsualSPStorageV0 storage $ = _usualSPStorageV0();
        return $.liquidAllocation[account];
    }

    /// @notice  Returns the total allocation of an account.
    /// @param account The address of the account.
    /// @return The total allocation.
    function balanceOf(address account) public view override returns (uint256) {
        UsualSPStorageV0 storage $ = _usualSPStorageV0();
        return
            $.liquidAllocation[account] + $.originalAllocation[account] - $.originalClaimed[account];
    }

    function totalStaked() public view override returns (uint256) {
        UsualSPStorageV0 storage $ = _usualSPStorageV0();
        return $.usualS.balanceOf(address(this));
    }

    /// @notice  Returns the vesting duration.
    /// @return  The duration.
    function getDuration() external view returns (uint256) {
        UsualSPStorageV0 storage $ = _usualSPStorageV0();
        return $.duration;
    }

    /// @notice  Returns the vesting cliff duration for an insider.
    /// @param insider The address of the insider.
    /// @return  The cliff duration of the insider.
    function getCliffDuration(address insider) external view returns (uint256) {
        UsualSPStorageV0 storage $ = _usualSPStorageV0();
        return $.cliffDuration[insider];
    }

    /// @notice  Returns the claimable amount of an insider.
    /// @param insider The address of the insider.
    /// @return The claimable amount.
    function getClaimableOriginalAllocation(address insider) external view returns (uint256) {
        UsualSPStorageV0 storage $ = _usualSPStorageV0();
        return _available($, insider);
    }

    /// @notice  Returns the claimed amount of an insider.
    /// @param insider The address of the insider.
    /// @return The claimed amount.
    function getClaimedAllocation(address insider) external view returns (uint256) {
        UsualSPStorageV0 storage $ = _usualSPStorageV0();
        return $.originalClaimed[insider];
    }

    // @notice Returns the current reward rate (rewards distributed per second)
    /// @return The reward rate
    function getRewardRate() external view returns (uint256) {
        RewardAccrualBaseStorageV0 storage $ = _getRewardAccrualBaseDataStorage();
        return $.rewardRate;
    }
}
