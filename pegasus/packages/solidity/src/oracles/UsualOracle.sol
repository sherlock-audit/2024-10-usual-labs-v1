// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {AbstractOracle} from "src/oracles/AbstractOracle.sol";
import {IDataPublisher} from "src/interfaces/oracles/IDataPublisher.sol";
import {CONTRACT_DATA_PUBLISHER} from "src/constants.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";
import {DEFAULT_ADMIN_ROLE, ONE_WEEK} from "src/constants.sol";
import {
    NullAddress,
    OracleNotWorkingNotCurrent,
    OracleNotInitialized,
    InvalidTimeout
} from "src/errors.sol";

/// @author  Usual Tech Team
/// @title   Usual Oracle System
/// @dev     This oracle redirects requests to a data publisher for various tokens.
/// @dev     It makes the price of these tokens available through a common interface.
contract UsualOracle is AbstractOracle {
    using CheckAccessControl for IRegistryAccess;

    struct UsualOracleStorageV0 {
        IDataPublisher dataPublisher;
    }

    // keccak256(abi.encode(uint256(keccak256("usualoracle.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant UsualOracleStorageV0Location =
        0x0c05d6b0a9814cbac33d40142603a5ac74985e5eb1b40d61a7da722cf07f9800;

    /// @notice Returns the storage struct of the contract.
    /// @return $ .
    function _usualOracleStorageV0() private pure returns (UsualOracleStorageV0 storage $) {
        bytes32 position = UsualOracleStorageV0Location;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := position
        }
    }

    /*//////////////////////////////////////////////////////////////
                             Constructor
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Constructor for initializing the contract.
    /// @dev This constructor is used to set the initial state of the contract.
    /// @param registryContractAddress The address of the registry contract address
    function initialize(address registryContractAddress) public initializer {
        __AbstractOracle_init_unchained(registryContractAddress);

        AbstractOracle.AbstractOracleStorageV0 storage $ = _abstractOracleStorageV0();
        UsualOracleStorageV0 storage u = _usualOracleStorageV0();
        u.dataPublisher = IDataPublisher($.registryContract.getContract(CONTRACT_DATA_PUBLISHER));
    }

    /// @notice Initialize a new supported token.
    /// @dev    When adding a new token, we assume that the provided oracle is working.
    /// @param  token        The address of the new token.
    /// @param  timeout      The timeout in seconds.
    /// @param  isStablecoin True if the token should be pegged to 1 USD, false otherwise.
    function initializeTokenOracle(address token, uint64 timeout, bool isStablecoin) external {
        if (token == address(0)) revert NullAddress();
        // The timeout can't be zero and must be at most one week
        if (timeout == 0 || timeout > ONE_WEEK) revert InvalidTimeout();

        AbstractOracle.AbstractOracleStorageV0 storage $ = _abstractOracleStorageV0();
        $.registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);

        UsualOracleStorageV0 storage u = _usualOracleStorageV0();

        // slither-disable-next-line unused-return
        (, int256 answer, uint256 timestamp,) = u.dataPublisher.latestRoundData(token);
        if (answer <= 0 || block.timestamp - timestamp > timeout) {
            revert OracleNotWorkingNotCurrent();
        }

        $.tokenToOracleInfo[token].dataSource = address(u.dataPublisher);
        $.tokenToOracleInfo[token].isStablecoin = isStablecoin;
    }

    /// @inheritdoc AbstractOracle
    function _latestRoundData(address token) internal view override returns (uint256, uint256) {
        AbstractOracle.AbstractOracleStorageV0 storage $ = _abstractOracleStorageV0();
        IDataPublisher dataPublisher = IDataPublisher($.tokenToOracleInfo[token].dataSource);

        if (address(dataPublisher) == address(0)) revert OracleNotInitialized();

        // slither-disable-next-line unused-return
        (, int256 answer,, uint256 decimals) = dataPublisher.latestRoundData(token);

        if (answer <= 0) revert OracleNotWorkingNotCurrent();

        return (uint256(answer), decimals);
    }
}
