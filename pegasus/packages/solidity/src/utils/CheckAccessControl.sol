// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";

import {NotAuthorized} from "src/errors.sol";

/// @title Check Access control library
library CheckAccessControl {
    /// @dev Function to restrict to one access role.
    /// @param registryAccess The registry access contract.
    /// @param role The role being checked.
    function onlyMatchingRole(IRegistryAccess registryAccess, bytes32 role) internal view {
        if (!registryAccess.hasRole(role, msg.sender)) {
            revert NotAuthorized();
        }
    }
}
