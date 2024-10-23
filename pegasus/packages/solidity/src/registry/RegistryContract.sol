// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IRegistryAccess} from "../interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "../interfaces/registry/IRegistryContract.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {DEFAULT_ADMIN_ROLE} from "src/constants.sol";

import {NotAuthorized, NullAddress, InvalidName} from "src/errors.sol";

/// @notice  This contract is used to store all the address of the contracts
/// @title   RegistryContract contract
/// @dev     This contract is used to store all the address of the contracts
/// @author  Usual Tech team
contract RegistryContract is IRegistryContract, Initializable {
    /*//////////////////////////////////////////////////////////////
                                Upgradability
    //////////////////////////////////////////////////////////////*/

    struct RegistryContractStorageV0 {
        mapping(bytes32 => address) _contracts;
        address _registryAccess;
    }

    /// @notice The position of the storage structure.
    // keccak256(abi.encode(uint256(keccak256("registrycontract.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant RegistryContractStorageV0Location =
        0xcf38fe916ff40451cdf6ceadfcd63ce28eb30d22d6d6be79c57435301c446700;

    /// @notice Returns the storage struct of the contract.
    /// @return $ .
    function _registryContractStorageV0()
        internal
        pure
        returns (RegistryContractStorageV0 storage $)
    {
        bytes32 position = RegistryContractStorageV0Location;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := position
        }
    }

    /*//////////////////////////////////////////////////////////////
                                Event
    //////////////////////////////////////////////////////////////*/

    /// @notice This event is emitted when the address of the contract is set
    /// @param name The name of the contract in bytes32
    /// @param contractAddress The address of the contract
    event SetContract(bytes32 indexed name, address indexed contractAddress);

    /*//////////////////////////////////////////////////////////////
                             Constructor
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Function for initializing the contract.
    /// @dev This function is used to set the initial state of the contract.
    /// @param registryAccess_ The address of the registry access contract.
    function initialize(address registryAccess_) public initializer {
        if (registryAccess_ == address(0)) {
            revert NullAddress();
        }

        RegistryContractStorageV0 storage $ = _registryContractStorageV0();
        $._registryAccess = registryAccess_;
    }

    /*//////////////////////////////////////////////////////////////
                               External
    //////////////////////////////////////////////////////////////*/

    /// @notice  Set the address of the contract
    /// @param   name  name of the contract
    /// @param   contractAddress  address of the contract
    function setContract(bytes32 name, address contractAddress) external {
        // if address is null reverts
        if (contractAddress == address(0)) {
            revert NullAddress();
        }
        // if name is null reverts
        if (name == bytes32(0)) {
            revert InvalidName();
        }

        RegistryContractStorageV0 storage $ = _registryContractStorageV0();
        // only admin can set the contract
        if (!IRegistryAccess($._registryAccess).hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAuthorized();
        }

        $._contracts[name] = contractAddress;
        emit SetContract(name, contractAddress);
    }

    /// @notice  Get the address of the contract
    /// @param   name  name of the contract
    /// @return  address  address of the contract
    function getContract(bytes32 name) external view returns (address) {
        RegistryContractStorageV0 storage $ = _registryContractStorageV0();
        address _contract = $._contracts[name];
        // if address is null reverts
        if (_contract == address(0)) {
            revert NullAddress();
        }

        return _contract;
    }
}
