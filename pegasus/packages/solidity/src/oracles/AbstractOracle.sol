// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {IOracle} from "src/interfaces/oracles/IOracle.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";
import {
    DEFAULT_ADMIN_ROLE,
    CONTRACT_REGISTRY_ACCESS,
    BASIS_POINT_BASE,
    INITIAL_MAX_DEPEG_THRESHOLD,
    SCALAR_ONE
} from "src/constants.sol";
import {StablecoinDepeg, NullAddress, SameValue, DepegThresholdTooHigh} from "src/errors.sol";
import {Normalize} from "src/utils/normalize.sol";

/// @author  Usual Tech Team
/// @title   Abstract Oracle contract
/// @dev     This contract returns the price of a token given its address.
/// @dev     It aggregates one Chainlink-compatible oracle per available token.
abstract contract AbstractOracle is IOracle, Initializable {
    using CheckAccessControl for IRegistryAccess;
    using Normalize for uint256;

    /// @notice Struct representing the oracle information for a token
    struct TokenOracle {
        address dataSource;
        /// @notice The oracle contract for the token
        bool isStablecoin;
        // timeout in seconds
        uint64 timeout;
    }
    /// @notice Flag indicating if the token is stable token

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /// @notice Event emitted when the value of the max depeg threshold change
    event SetMaxDepegThreshold(uint256 newMaxDepegThreshold);

    /*//////////////////////////////////////////////////////////////
                                Storage
    //////////////////////////////////////////////////////////////*/

    // Storage struct of the contract
    struct AbstractOracleStorageV0 {
        IRegistryContract registryContract;
        IRegistryAccess registryAccess;
        /// @notice mapping to get all oracle information from a token
        mapping(address token => TokenOracle) tokenToOracleInfo;
        uint256 maxDepegThreshold;
    }

    // keccak256(abi.encode(uint256(keccak256("abstractoracle.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant AbstractOracleStorageV0Location =
        0x51aa7d76d8341fbde5c4ba9b425bca5cb989c0653f626e6ddb9e8c525c168300;

    /// @notice Returns the storage struct of the contract.
    /// @return $ The pointer to the storage struct of the contract.
    function _abstractOracleStorageV0() internal pure returns (AbstractOracleStorageV0 storage $) {
        bytes32 position = AbstractOracleStorageV0Location;
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
    /// @dev    This constructor is used to set the initial state of the contract.
    /// @param  registryContract The registry contract address.
    // solhint-disable-next-line func-name-mixedcase
    function __AbstractOracle_init_unchained(address registryContract) internal onlyInitializing {
        if (registryContract == address(0)) {
            revert NullAddress();
        }

        AbstractOracleStorageV0 storage $ = _abstractOracleStorageV0();
        $.registryContract = IRegistryContract(registryContract);
        $.registryAccess = IRegistryAccess($.registryContract.getContract(CONTRACT_REGISTRY_ACCESS));
        $.maxDepegThreshold = INITIAL_MAX_DEPEG_THRESHOLD;
        emit SetMaxDepegThreshold(INITIAL_MAX_DEPEG_THRESHOLD);
    }

    /// @notice Get the maximum allowed depeg threshold for stablecoins.
    /// @dev    The returned value is in basis points relative to 1 USD.
    /// @dev    Valid values are from 0 (exact 1:1 peg required) to 10_000 ($0.00-$2.00 allowed).
    /// @dev    getPrice will revert if the price falls outside of this range.
    /// @return The maximum allowed depeg threshold in basis points.
    function getMaxDepegThreshold() external view returns (uint256) {
        AbstractOracle.AbstractOracleStorageV0 storage $ = _abstractOracleStorageV0();
        return $.maxDepegThreshold;
    }

    /// @notice Set the maximum allowed depeg threshold for stablecoins.
    /// @dev    The provided value should be in basis points relative to 1 USD.
    /// @dev    Valid values are from 0 (exact 1:1 peg required) to 10_000 ($0.00-$2.00 allowed).
    /// @dev    getPrice will revert if the price falls outside of this range.
    /// @param  maxAuthorizedDepegPrice The new maximum allowed depeg threshold.
    function setMaxDepegThreshold(uint256 maxAuthorizedDepegPrice) external virtual {
        if (maxAuthorizedDepegPrice > BASIS_POINT_BASE) revert DepegThresholdTooHigh();

        AbstractOracleStorageV0 storage $ = _abstractOracleStorageV0();
        $.registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);

        if ($.maxDepegThreshold == maxAuthorizedDepegPrice) revert SameValue();
        $.maxDepegThreshold = maxAuthorizedDepegPrice;
        emit SetMaxDepegThreshold(maxAuthorizedDepegPrice);
    }

    // --- Functions ---

    /// @inheritdoc IOracle
    function getPrice(address token) public view override returns (uint256) {
        (uint256 price, uint256 decimalsPrice) = _latestRoundData(token);
        price = price.tokenAmountToWad(uint8(decimalsPrice));
        _checkDepegPrice(token, price);
        return price;
    }

    /// @inheritdoc IOracle
    function getQuote(address token, uint256 amount) external view override returns (uint256) {
        return Math.mulDiv(getPrice(token), amount, SCALAR_ONE);
    }

    /*//////////////////////////////////////////////////////////////
                                Helpers
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the most recent oracle response for a token.
    /// @param  token    The address of the token
    /// @return price    The most recent oracle response.
    /// @return decimals The amount of decimals for the price.
    function _latestRoundData(address token)
        internal
        view
        virtual
        returns (uint256 price, uint256 decimals);

    /// @notice Check if a given token's price is around 1 USD.
    /// @dev    Reverts if the stablecoin has depegged.
    /// @dev    The allowed range is determined by maxDepegThreshold.
    /// @param  token         The address of the token.
    /// @param  wadPriceInUSD The price of the token returned by the underlying oracle.
    function _checkDepegPrice(address token, uint256 wadPriceInUSD) internal view {
        AbstractOracleStorageV0 storage $ = _abstractOracleStorageV0();

        // Skip the check if the token is not a stablecoin
        if (!$.tokenToOracleInfo[token].isStablecoin) return;

        uint256 threshold = Math.mulDiv($.maxDepegThreshold, SCALAR_ONE, BASIS_POINT_BASE);

        if (wadPriceInUSD > SCALAR_ONE + threshold || wadPriceInUSD < SCALAR_ONE - threshold) {
            revert StablecoinDepeg();
        }
    }
}
