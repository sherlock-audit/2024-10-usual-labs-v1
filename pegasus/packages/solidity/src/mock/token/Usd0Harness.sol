// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Usd0} from "src/token/Usd0.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";

import {CONTRACT_REGISTRY_ACCESS} from "src/constants.sol";
import {NullContract} from "src/errors.sol";

contract Usd0Harness is Usd0 {
    /*//////////////////////////////////////////////////////////////
                             INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice  Initializes the contract with a registry contract, name, and symbol.
    /// @param   registryContract_ Address of the registry contract for role management.
    /// @param   name_ The name of the USD0 token.
    /// @param   symbol_ The symbol of the USD0 token.
    function initialize(address registryContract_, string memory name_, string memory symbol_)
        public
        initializer
    {
        // Initialize the contract with token details.
        __ERC20_init_unchained(name_, symbol_);
        // Initialize the contract in an unpaused state.
        __Pausable_init_unchained();
        // Initialize the contract with permit functionality.
        __ERC20Permit_init_unchained(name_);
        // Initialize the contract with EIP712 functionality.
        __EIP712_init_unchained(name_, "1");
        // Initialize the contract with the registry contract.
        if (registryContract_ == address(0)) {
            revert NullContract();
        }
        _usd0StorageV0().registryAccess = IRegistryAccess(
            IRegistryContract(registryContract_).getContract(CONTRACT_REGISTRY_ACCESS)
        );
    }

    /// @notice  Initializes the contract with a registry contract.
    /// @param   registryContract_ Address of the registry contract for role management.
    function initializeV1(IRegistryContract registryContract_) public reinitializer(2) {
        // Initialize the contract with the registry contract.
        if (address(registryContract_) == address(0)) {
            revert NullContract();
        }
        Usd0StorageV0 storage $ = _usd0StorageV0();
        $.registryContract = registryContract_;
        $.registryAccess = IRegistryAccess(registryContract_.getContract(CONTRACT_REGISTRY_ACCESS));
    }
}
