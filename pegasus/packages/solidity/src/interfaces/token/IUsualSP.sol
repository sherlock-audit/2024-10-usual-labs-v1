// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface IUsualSP {
    /// @notice claim UsualS token from allocation
    /// @dev After the cliff period, the owner can claim UsualS token every month during the vesting period
    function claimOriginalAllocation() external;

    /// @notice stake UsualS token to the contract
    /// @param amount the amount of UsualS token to stake
    function stake(uint256 amount) external;

    /// @notice stake UsualS token to the contract with permit
    /// @param amount the amount of UsualS token to stake
    /// @param deadline the deadline of the permit
    /// @param v the v of the permit
    /// @param r the r of the permit
    /// @param s the s of the permit
    function stakeWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    /// @notice unstake UsualS token from the contract
    /// @param amount the amount of UsualS token to unstake
    function unstake(uint256 amount) external;

    /// @notice claim reward from the contract
    /// @return the amount of reward token claimed
    function claimReward() external returns (uint256);

    /// @notice Allocate UsualSP token to the recipients
    /// @dev Can only be called by the admin
    /// @param recipients the list of recipients
    /// @param originalAllocations the list of allocations
    /// @param cliffDurations the list of cliffDurations
    function allocate(
        address[] calldata recipients,
        uint256[] calldata originalAllocations,
        uint256[] calldata cliffDurations
    ) external;

    /// @notice Remove the allocation of UsualSP token from the recipients
    /// @dev Can only be called by the admin
    /// @param recipients the list of recipients
    function removeOriginalAllocation(address[] calldata recipients) external;

    /// @notice claim every UsualS token from UsualS contract
    /// @dev Can only be called by the admin
    function stakeUsualS() external;

    /// @notice start reward distribution
    /// @dev Can only be called by the distribution module contract
    /// @param amount the amount of reward token to distribute
    /// @param startTime the start time of the reward distribution
    /// @param endTime the end time of the reward distribution
    function startRewardDistribution(uint256 amount, uint256 startTime, uint256 endTime) external;
}
