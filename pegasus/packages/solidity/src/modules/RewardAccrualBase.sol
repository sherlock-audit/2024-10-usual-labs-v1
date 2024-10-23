// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {
    AmountIsZero, EndTimeBeforeStartTime, StartTimeInPast, AlreadyStarted
} from "../errors.sol";

/**
 * @title RewardAccrualBase
 * @dev Abstract contract for handling reward accrual logic where shares appreciate in value over time.
 * This contract manages the accumulation and claiming of rewards for users based on their share of the total supply.
 */
abstract contract RewardAccrualBase {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @custom:storage-location erc7201:RewardAccrualBase.storage.v0
    struct RewardAccrualBaseStorageV0 {
        uint256 periodStart; // Start time of the current reward period
        uint256 periodFinish; // End time of the current reward period
        uint256 lastUpdateTime; // Last time the reward was updated
        IERC20 rewardToken; // Token used for reward distribution
        uint256 rewardAmount; // The amount of rewards deposited by distribution module
        uint256 rewardRate; // The amount of rewards distributed per second
        uint256 rewardPerTokenStored; // The amount of rewards per token stored
        mapping(address => uint256) lastRewardPerTokenUsed; // The amount of rewards per token paid to user
        mapping(address => uint256) rewards; // The amount of rewards earned by user
    }

    // solhint-disable
    //keccak256(abi.encode(uint256(keccak256("rewardaccrualbase.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RewardAccrualBaseStorageV0StorageLocation =
        0xece341a81e9ef81761e1d1d3338155bec39de2969454f2b1605e36884716e500;

    /**
     * @dev Internal function to access the RewardAccrualBaseDataStorage
     * @return $ The RewardAccrualBaseStorageV0 struct
     */
    function _getRewardAccrualBaseDataStorage()
        internal
        pure
        returns (RewardAccrualBaseStorageV0 storage $)
    {
        assembly {
            $.slot := RewardAccrualBaseStorageV0StorageLocation
        }
    }

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emitted when a user claims their reward
     */
    event RewardClaimed(address indexed user, uint256 reward);

    /**
     * @dev Emitted when a new reward period starts
     */
    event RewardPeriodStarted(uint256 rewardAmount, uint256 startTime, uint256 endTime);

    /**
     * @dev Emitted when the reward rate changes
     */
    event RewardRateChanged(uint256 rewardRate);

    /*//////////////////////////////////////////////////////////////
                             INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Initializes the contract
     * @param _rewardToken The address of the reward token
     */
    function __RewardAccrualBase_init(address _rewardToken) internal {
        __RewardAccrualBase_init_unchained(_rewardToken);
    }

    /**
     * @dev Initializes the contract (unchained version)
     * @param _rewardToken The address of the reward token
     */
    function __RewardAccrualBase_init_unchained(address _rewardToken) internal {
        RewardAccrualBaseStorageV0 storage $ = _getRewardAccrualBaseDataStorage();
        $.periodStart = 0;
        $.periodFinish = 0;
        $.lastUpdateTime = 0;
        $.rewardToken = IERC20(_rewardToken); // Null check is done by importing contract
        $.rewardAmount = 0;
        $.rewardRate = 0;
        $.rewardPerTokenStored = 0;
    }

    /*//////////////////////////////////////////////////////////////
                               Internal
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Calculates the rewards per token at the contract level
     * @return rewardPerToken The rewards per token at the contract level
     */
    function _rewardPerToken() internal view virtual returns (uint256 rewardPerToken) {
        RewardAccrualBaseStorageV0 storage $ = _getRewardAccrualBaseDataStorage();
        uint256 timeElapsed;
        // slither-disable-next-line incorrect-equality
        if (totalStaked() == 0) {
            return $.rewardPerTokenStored;
        } else {
            if ($.periodFinish == 0) {
                timeElapsed = block.timestamp - $.lastUpdateTime;
            } else {
                uint256 end = Math.min(block.timestamp, $.periodFinish);
                if ($.lastUpdateTime < end) {
                    timeElapsed = end - $.lastUpdateTime;
                } else {
                    timeElapsed = 0;
                }
            }
            uint256 rewardIncrease = $.rewardRate * timeElapsed;
            rewardPerToken = $.rewardPerTokenStored
                + rewardIncrease.mulDiv(1e24, totalStaked(), Math.Rounding.Floor); // 1e6 for precision loss
        }
    }

    /**
     * @dev Calculates the earned rewards for a given account
     * @param account The address of the account
     * @return earned The amount of rewards earned
     */
    function _earned(address account) internal view virtual returns (uint256 earned) {
        RewardAccrualBaseStorageV0 storage $ = _getRewardAccrualBaseDataStorage();
        uint256 accountBalance = balanceOf(account);
        uint256 rewardDelta = $.rewardPerTokenStored - $.lastRewardPerTokenUsed[account];
        earned = accountBalance.mulDiv(rewardDelta, 1e24, Math.Rounding.Floor) + $.rewards[account]; // 1e24 for precision loss
    }

    /**
     * @dev Claims rewards for the caller
     * @return rewardsClaimed The amount of rewards claimed
     */
    function _claimRewards() internal virtual returns (uint256 rewardsClaimed) {
        RewardAccrualBaseStorageV0 storage $ = _getRewardAccrualBaseDataStorage();
        _updateReward(msg.sender);
        rewardsClaimed = $.rewards[msg.sender];
        $.rewards[msg.sender] = 0;
        $.rewardToken.safeTransfer(msg.sender, rewardsClaimed);
        emit RewardClaimed(msg.sender, rewardsClaimed);
    }

    /**
     * @dev Updates the reward state for a given account
     * @param account The address of the account to update
     */
    function _updateReward(address account) internal virtual {
        RewardAccrualBaseStorageV0 storage $ = _getRewardAccrualBaseDataStorage();
        if (block.timestamp > $.lastUpdateTime) {
            $.rewardPerTokenStored = _rewardPerToken();
            $.lastUpdateTime = block.timestamp;
        }
        $.rewards[account] = _earned(account);
        $.lastRewardPerTokenUsed[account] = $.rewardPerTokenStored;
    }

    /**
     * @dev Updates the reward state for a new reward distribution period
     *
     */
    function _updateRewardDistribution() internal virtual {
        RewardAccrualBaseStorageV0 storage $ = _getRewardAccrualBaseDataStorage();
        $.rewardPerTokenStored = _rewardPerToken();
        $.lastUpdateTime = block.timestamp;
    }

    /**
     * @dev Starts a new reward distribution period
     * @param rewardAmount Amount of rewards to distribute over the next period
     * @param startTime Start time of the new reward period
     * @param endTime End time of the new reward period
     */
    function _startRewardDistribution(uint256 rewardAmount, uint256 startTime, uint256 endTime)
        internal
        virtual
    {
        if (endTime <= startTime) {
            revert EndTimeBeforeStartTime();
        }
        if (startTime < block.timestamp) {
            revert StartTimeInPast();
        }

        if (rewardAmount == 0) {
            revert AmountIsZero();
        }

        RewardAccrualBaseStorageV0 storage $ = _getRewardAccrualBaseDataStorage();

        if (startTime < $.periodFinish) {
            revert AlreadyStarted();
        }

        // Update reward state to the current block timestamp
        _updateRewardDistribution();

        // Set new reward distribution period parameters
        $.periodStart = startTime;
        $.periodFinish = endTime;

        // Calculate reward rate: rewards per second
        // slither-disable-next-line divide-before-multiply

        uint256 duration = endTime - startTime;
        $.rewardRate = rewardAmount / duration;
        // Adjust reward amount to match what will actually be paid out
        uint256 adjustedAmount = $.rewardRate * duration;
        $.rewardAmount = adjustedAmount;

        // Ensure the reward amount is properly transferred to the vault
        $.rewardToken.safeTransferFrom(msg.sender, address(this), adjustedAmount);

        emit RewardPeriodStarted(adjustedAmount, startTime, endTime);
        emit RewardRateChanged($.rewardRate);
    }

    /**
     * @dev Returns the balance of shares of the given account
     * @dev This function is overridden by the child contract
     * @param account The address of the account
     * @return The balance of the account
     */
    function balanceOf(address account) public view virtual returns (uint256) {}

    /**
     * @dev Returns the total staked amount
     * @dev This function is overridden by the child contract
     * @return The total staked amount
     */
    function totalStaked() public view virtual returns (uint256) {}
}
