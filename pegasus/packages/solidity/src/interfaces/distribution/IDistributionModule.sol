// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface IDistributionModule {
    struct QueuedOffChainDistribution {
        /// @notice Timestamp of the queued distribution
        uint256 timestamp;
        /// @notice Merkle root of the queued distribution
        bytes32 merkleRoot;
    }

    /// @notice Returns the current buckets distribution percentage for the Usual token emissions (in basis points)
    /// @return lbt LBT bucket percentage
    /// @return lyt LYT bucket percentage
    /// @return iyt IYT bucket percentage
    /// @return bribe Bribe bucket percentage
    /// @return eco Eco bucket percentage
    /// @return dao DAO bucket percentage
    /// @return marketMakers MarketMakers bucket percentage
    /// @return usualP UsualP bucket percentage
    /// @return usualStar UsualStar bucket percentage
    function getBucketsDistribution()
        external
        view
        returns (
            uint256 lbt,
            uint256 lyt,
            uint256 iyt,
            uint256 bribe,
            uint256 eco,
            uint256 dao,
            uint256 marketMakers,
            uint256 usualP,
            uint256 usualStar
        );

    /// @notice Calculates the St value
    /// @dev Raw equation: St = min((supplyPp0 * p0) / (supplyPpt * pt), 1)
    /// @param supplyPpt Current supply (scaled by SCALAR_ONE)
    /// @param pt Current price (scaled by SCALAR_ONE)
    /// @return St value (scaled by SCALAR_ONE)
    function calculateSt(uint256 supplyPpt, uint256 pt) external view returns (uint256);

    /// @notice Calculates the Rt value
    /// @dev Raw equation: Rt = min( max(ratet, rateMin), p90Rate ) / rate0
    /// @param ratet Current rate (scaled by BPS_SCALAR)
    /// @param p90Rate 90th percentile rate (scaled by BPS_SCALAR)
    /// @return Rt value (scaled by SCALAR_ONE)
    function calculateRt(uint256 ratet, uint256 p90Rate) external view returns (uint256);

    /// @notice Calculates the Kappa value
    /// @dev Raw equation: Kappa = m_0*max(rate_t[i],rate_min)/rate_0
    /// @param ratet Current rate (scaled by BPS_SCALAR)
    /// @return Kappa value (scaled by SCALAR_ONE)
    function calculateKappa(uint256 ratet) external view returns (uint256);

    /// @notice Calculates the Mt value
    /// @dev Raw equation: Mt = min((m0 * St * Rt)/gamma, kappa)
    /// @param st St value (scaled by SCALAR_ONE)
    /// @param rt Rt value (scaled by SCALAR_ONE)
    /// @param kappa Kappa value (in basis points)
    /// @return Mt value (scaled by SCALAR_ONE)
    function calculateMt(uint256 st, uint256 rt, uint256 kappa) external view returns (uint256);

    /// @notice Calculates all values: St, Rt, Mt, and UsualDist
    /// @param ratet Current rate (scaled by BPS_SCALAR)
    /// @param p90Rate 90th percentile rate (scaled by BPS_SCALAR)
    /// @return st St value (scaled by SCALAR_ONE)
    /// @return rt Rt value (scaled by SCALAR_ONE)
    /// @return kappa Kappa value (scaled by SCALAR_ONE)
    /// @return mt Mt value (scaled by SCALAR_ONE)
    /// @return usualDist UsualDist value (raw, not scaled)
    function calculateUsualDist(uint256 ratet, uint256 p90Rate)
        external
        view
        returns (uint256 st, uint256 rt, uint256 kappa, uint256 mt, uint256 usualDist);

    /// @notice Claims the Usual token distribution for the given account
    /// @param account The account to claim for
    /// @param amount Total amount of Usual token rewards earned by the account up to this point
    /// @param proof Merkle proof
    function claimOffChainDistribution(address account, uint256 amount, bytes32[] calldata proof)
        external;

    /// @notice Returns the current off-chain distribution data
    /// @return timestamp Timestamp of the latest unchallanged distribution
    /// @return merkleRoot Merkle root of the latest unchallanged distribution
    function getOffChainDistributionData()
        external
        view
        returns (uint256 timestamp, bytes32 merkleRoot);

    /// @notice Returns the amount of Usual token claimed off-chain by the account up to this point
    /// @param account The account to check
    /// @return amount Amount of Usual token claimed off-chain
    function getOffChainTokensClaimed(address account) external view returns (uint256 amount);

    /// @notice Returns the off-chain distribution queue
    /// @return QueuedOffChainDistribution[] Array of queued off-chain distributions
    function getOffChainDistributionQueue()
        external
        view
        returns (QueuedOffChainDistribution[] memory);

    /// @notice Returns maximum amount of Usual token that can be distributed off-chain
    /// @return amount Maximum amount of Usual token that can be distributed off-chain
    function getOffChainDistributionMintCap() external view returns (uint256 amount);

    /// @notice Returns the timestamp of the last on-chain distribution
    /// @return timestamp Timestamp of the last on-chain distribution
    function getLastOnChainDistributionTimestamp() external view returns (uint256 timestamp);

    /// @notice Approve the latest queue merkle root that is unchallenged and older than challenge period.
    /// @dev Every queued merkle root older than challenge period will be removed.
    function approveUnchallengedOffChainDistribution() external;
}
