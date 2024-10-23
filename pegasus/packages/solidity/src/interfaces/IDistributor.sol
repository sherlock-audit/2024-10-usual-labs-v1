// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface IDistributor {
    /// @notice Distribute the profitBalance of the bucket
    /// @dev This function should only callable by the bucketDistribution contract
    /// @param bucket The bucket to distribute the profitBalance to
    /// @param token The token address to be distrbute
    /// @param profitBalance The profitBalance to distribute
    /// @param receiver a receiver address
    /// @return profitDistributed profit amount actually distributed out of the profitBalance
    function distribute(bytes32 bucket, address token, uint256 profitBalance, address receiver)
        external
        returns (uint256 profitDistributed);
}
