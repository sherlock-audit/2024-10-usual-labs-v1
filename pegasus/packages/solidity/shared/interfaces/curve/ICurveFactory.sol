// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

/// @notice Curve Factory interface
/// @notice Permissionless pool deployer and registry
interface ICurveFactory {
    event BasePoolAdded(address base_pool);

    event PlainPoolDeployed(address[] coins, uint256 A, uint256 fee, address deployer);

    event MetaPoolDeployed(
        address coin, address base_pool, uint256 A, uint256 fee, address deployer
    );

    event LiquidityGaugeDeployed(address pool, address gauge);

    /// @notice Deploy a new curve pool
    /// @param _name Pool name
    /// @param _symbol Pool symbol
    /// @param _coins Underlying tokens
    /// @param _A Amplification coefficient
    /// @param _fee Fee
    /// @param _offpeg_fee_multiplier Offpeg fee multiplier
    /// @param _ma_exp_time Moving average expiration time
    /// @param _implementation_idx Implementation index
    /// @param _asset_types Asset types
    /// @param _method_ids Method IDs
    /// @param _oracles Oracles
    /// @return Pool address
    function deploy_plain_pool(
        string memory _name,
        string memory _symbol,
        address[] memory _coins,
        uint256 _A,
        uint256 _fee,
        uint256 _offpeg_fee_multiplier,
        uint256 _ma_exp_time,
        uint256 _implementation_idx,
        uint8[] memory _asset_types,
        bytes4[] memory _method_ids,
        address[] memory _oracles
    ) external returns (address);

    /// @notice Deploy a new curve pool
    /// @param _pool Pool address
    /// @return gauge address
    function deploy_gauge(address _pool) external returns (address);

    /// @notice Find an available pool for exchanging two coins
    /// @param _from Address of coin to be sent
    /// @param _to Address of coin to be received
    /// @return Pool address
    function find_pool_for_coins(address _from, address _to) external view returns (address);

    /// @notice Find an available pool for exchanging two coins
    /// @param _from Address of coin to be sent
    /// @param _to Address of coin to be received
    /// @param i Index value. When multiple pools are available
    ///         this value is used to return the n'th address.
    /// @return Pool address
    function find_pool_for_coins(address _from, address _to, uint256 i)
        external
        view
        returns (address);

    /// @notice Get the coins within a pool
    /// @param _pool Pool address
    /// @return List of coin addresses
    function get_coins(address _pool) external view returns (address[] memory);

    /// @notice Get the address of the liquidity gauge contract for a factory pool
    /// @dev Returns `empty(address)` if a gauge has not been deployed
    /// @param _pool Pool address
    /// @return Implementation contract address
    function get_gauge(address _pool) external view returns (address);
}
