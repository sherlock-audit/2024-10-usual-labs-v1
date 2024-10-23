// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {ITokenMapping} from "src/interfaces/tokenManager/ITokenMapping.sol";
import {IERC20Metadata} from "openzeppelin-contracts/interfaces/IERC20Metadata.sol";
import {DEFAULT_ADMIN_ROLE, MAX_RWA_COUNT} from "src/constants.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";

import {NullAddress, InvalidToken, SameValue, Invalid, TooManyRWA} from "src/errors.sol";

/// @title   TokenMapping contract
/// @notice  TokenMapping contract to manage Rwa, Usd0, and Lp tokens.
/// @dev     This contract provides functionalities to link Real World Assets (RWA) tokens with Stable Coin (Usd0) tokens and manage token pairs.
/// @dev     It's part of the Usual Tech team's broader ecosystem to facilitate various operations within the platform.
/// @author  Usual Tech team
contract TokenMapping is ITokenMapping, Initializable {
    using CheckAccessControl for IRegistryAccess;

    struct TokenMappingStorageV0 {
        /// @notice Immutable instance of the REGISTRY_ACCESS contract for role checks.
        IRegistryAccess _registryAccess;
        /// @notice Immutable instance of the REGISTRY_CONTRACT for contract interaction.
        IRegistryContract _registryContract;
        /// @dev track last associated RWA ID associated to USD0.
        uint256 _usd0ToRwaLastId;
        /// @dev assign a RWA token address to USD0 token address.
        mapping(address => bool) isUsd0Collateral;
        /// @dev  RWA ID associated with USD0 token address.
        // solhint-disable-next-line var-name-mixedcase
        mapping(uint256 => address) USD0Rwas;
    }

    // keccak256(abi.encode(uint256(keccak256("tokenmapping.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant TokenMappingStorageV0Location =
        0xb0e2a10694f571e49337681df93856b25ecda603d0f0049769ee36b541ef2300;

    /// @notice Returns the storage struct of the contract.
    /// @return $ .
    function _tokenMappingStorageV0() private pure returns (TokenMappingStorageV0 storage $) {
        bytes32 position = TokenMappingStorageV0Location;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := position
        }
    }

    /*//////////////////////////////////////////////////////////////
                            Events
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an RWA token is linked to USD0 token.
    /// @param rwa The address of the RWA token.
    /// @param rwaId The ID of the RWA token.
    event AddUsd0Rwa(address indexed rwa, uint256 indexed rwaId);

    /*//////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the TokenMapping contract with registry information.
    /// @dev Sets the registry access and contract addresses upon deployment.
    /// @param registryAccess The address of the registry access contract.
    /// @param registryContract The address of the registry contract.
    function initialize(address registryAccess, address registryContract) public initializer {
        if (registryAccess == address(0) || registryContract == address(0)) {
            revert NullAddress();
        }

        TokenMappingStorageV0 storage $ = _tokenMappingStorageV0();
        $._registryAccess = IRegistryAccess(registryAccess);
        $._registryContract = IRegistryContract(registryContract);
    }

    /// @inheritdoc ITokenMapping
    function addUsd0Rwa(address rwa) external returns (bool) {
        if (rwa == address(0)) {
            revert NullAddress();
        }
        // check if there is a decimals function at the address
        // and if there is at least 1 decimal
        // if not, revert
        if (IERC20Metadata(rwa).decimals() == 0) {
            revert Invalid();
        }

        TokenMappingStorageV0 storage $ = _tokenMappingStorageV0();
        $._registryAccess.onlyMatchingRole(DEFAULT_ADMIN_ROLE);

        // is the RWA already registered as a USD0 RWA
        if ($.isUsd0Collateral[rwa]) revert SameValue();
        $.isUsd0Collateral[rwa] = true;
        // 0 index is always empty
        ++$._usd0ToRwaLastId;
        if ($._usd0ToRwaLastId > MAX_RWA_COUNT) {
            revert TooManyRWA();
        }
        $.USD0Rwas[$._usd0ToRwaLastId] = rwa;
        emit AddUsd0Rwa(rwa, $._usd0ToRwaLastId);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                                 View
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ITokenMapping
    function getUsd0RwaById(uint256 rwaId) external view returns (address) {
        TokenMappingStorageV0 storage $ = _tokenMappingStorageV0();
        address rwa = $.USD0Rwas[rwaId];
        if (rwa == address(0)) {
            revert InvalidToken();
        }
        return rwa;
    }

    /// @inheritdoc ITokenMapping
    function getAllUsd0Rwa() external view returns (address[] memory) {
        TokenMappingStorageV0 storage $ = _tokenMappingStorageV0();
        address[] memory rwas = new address[]($._usd0ToRwaLastId);
        // maximum of 10 rwa tokens
        uint256 length = $._usd0ToRwaLastId;
        for (uint256 i = 1; i <= length;) {
            rwas[i - 1] = $.USD0Rwas[i];
            unchecked {
                ++i;
            }
        }
        return rwas;
    }

    /// @inheritdoc ITokenMapping
    function getLastUsd0RwaId() external view returns (uint256) {
        TokenMappingStorageV0 storage $ = _tokenMappingStorageV0();
        return $._usd0ToRwaLastId;
    }

    /// @inheritdoc ITokenMapping
    function isUsd0Collateral(address rwa) external view returns (bool) {
        TokenMappingStorageV0 storage $ = _tokenMappingStorageV0();
        return $.isUsd0Collateral[rwa];
    }
}
