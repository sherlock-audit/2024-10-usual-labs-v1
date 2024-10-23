// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface IOffChainDistributionChallenger {
    /// @notice Challenges all queued off-chain distribution older than specified timestamp.
    /// @param _timestamp Timestamp before which the off-chain distribution will be challenged
    /// @dev Can be only called by the DISTRIBUTION_CHALLENGER role
    function challengeOffChainDistribution(uint256 _timestamp) external;
}
