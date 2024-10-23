// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

interface IDistributionAllocator {
    /// @notice Sets the buckets distribution percentages for the Usual token emissions
    /// @param _lbt LBT bucket percentage
    /// @param _lyt LYT bucket percentage
    /// @param _iyt IYT bucket percentage
    /// @param _bribe Bribe bucket percentage
    /// @param _eco Eco bucket percentage
    /// @param _dao DAO bucket percentage
    /// @param _marketMakers MarketMakers bucket percentage
    /// @param _usualP UsualP bucket percentage
    /// @param _usualStar UsualStar bucket percentage
    /// @dev The sum of all percentages should be equal to BASIS_POINT_BASE (100% - in basis points)
    /// @dev Can be only called by the DISTRIBUTION_ALLOCATOR role
    function setBucketsDistribution(
        uint256 _lbt,
        uint256 _lyt,
        uint256 _iyt,
        uint256 _bribe,
        uint256 _eco,
        uint256 _dao,
        uint256 _marketMakers,
        uint256 _usualP,
        uint256 _usualStar
    ) external;

    /// @notice Sets D parameter used for the Usual token emissions distribution calculation
    /// @param _d D parameter
    function setD(uint256 _d) external;

    /// @notice Returns the D parameter used for the Usual token emissions distribution calculation
    /// @return d D parameter
    function getD() external view returns (uint256 d);

    /// @notice Sets M0 parameter used for the Usual token emissions distribution calculation
    /// @param _m0 M0 parameter
    function setM0(uint256 _m0) external;

    /// @notice Returns the M0 parameter used for the Usual token emissions distribution calculation
    /// @return m0 M0 parameter
    function getM0() external view returns (uint256 m0);

    /// @notice Sets rateMin parameter used for the Usual token emissions distribution calculation
    /// @param _rateMin rate0 parameter
    function setRateMin(uint256 _rateMin) external;

    /// @notice Returns the rateMin parameter used for the Usual token emissions distribution calculation
    /// @return rateMin rateMin parameter
    function getRateMin() external view returns (uint256 rateMin);

    /// @notice Sets gamma parameter used for the Usual token emissions distribution calculation
    /// @param _gamma rateMin parameter
    function setBaseGamma(uint256 _gamma) external;

    /// @notice Returns the gamma parameter used for the Usual token emissions distribution calculation
    /// @return gamma gamma parameter
    function getBaseGamma() external view returns (uint256 gamma);
}
