// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Usd0PP} from "src/token/Usd0PP.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {CONTRACT_REGISTRY_ACCESS, CONTRACT_USD0} from "src/constants.sol";
import {NullContract, InvalidName, InvalidSymbol, BeginInPast} from "src/errors.sol";

contract Usd0PPHarness is Usd0PP {
    /*//////////////////////////////////////////////////////////////
                             INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with bond parameters and related registry and token information.
    /// @dev  The end time of the bond period will be four years later.
    /// @param registryContract The address of the registry contract.
    /// @param name_ The name of the bond token.
    /// @param symbol_ The symbol of the bond token.
    /// @param startTime The start time of the bond period.
    // solhint-disable code-complexity
    function initialize(
        address registryContract,
        string memory name_,
        string memory symbol_,
        uint256 startTime
    ) public initializer {
        _createUsd0PPCheck(name_, symbol_, startTime);

        __ERC20_init_unchained(name_, symbol_);
        __ERC20Permit_init_unchained(name_);
        __EIP712_init_unchained(name_, "1");
        __ReentrancyGuard_init_unchained();
        // Create the bond token
        Usd0PPStorageV0 storage $ = _usd0ppStorageV0();
        $.bondStart = startTime;
        $.registryContract = IRegistryContract(registryContract);
        $.usd0 = IERC20(IRegistryContract(registryContract).getContract(CONTRACT_USD0));
        $.registryAccess = IRegistryAccess(
            IRegistryContract(registryContract).getContract(CONTRACT_REGISTRY_ACCESS)
        );
    }

    function _createUsd0PPCheck(string memory name, string memory symbol, uint256 startTime)
        internal
        view
    {
        // Check if the bond start date is after now
        if (startTime < block.timestamp) {
            revert BeginInPast();
        }
        // Check if the name is not empty
        if (bytes(name).length == 0) {
            revert InvalidName();
        }
        // Check if the symbol is not empty
        if (bytes(symbol).length == 0) {
            revert InvalidSymbol();
        }
    }
}
