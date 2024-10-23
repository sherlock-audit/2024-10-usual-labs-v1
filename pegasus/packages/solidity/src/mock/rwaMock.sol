// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC20Whitelist} from "./ERC20Whitelist.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IRwaMock} from "src/interfaces/token/IRwaMock.sol";

/// @author  Usual Tech team
/// @title   RwaMock contract
/// @notice  The purpose of this contract is to mock the Rwa token
/// @dev     Since this contract will be done by Tokeny the implementation is classic
contract RwaMock is ERC20Whitelist, IRwaMock {
    using SafeERC20 for ERC20;

    uint8 private _decimals;
    /*//////////////////////////////////////////////////////////////
                             Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 decimals_,
        address _registryContract
    ) ERC20Whitelist(_registryContract, _name, _symbol) {
        _decimals = decimals_;
    }

    /*//////////////////////////////////////////////////////////////
                               External
    //////////////////////////////////////////////////////////////*/
    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return _decimals;
    }

    // set decimals
    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }

    /// @notice  Mint rwa token
    /// @param   to  address of the account you want to receive
    /// @param   amount the amount of token you want to mint
    function mint(address to, uint256 amount) public {
        // solhint-disable-next-line custom-errors
        require(to != address(0), "Address must be a valid address");
        _mint(to, amount);
    }

    /// @notice  Burn rwa token
    /// @param   account  address of the account you want to burn
    /// @param   amount  the amount of token you want to burn
    function burnFrom(address account, uint256 amount) public {
        _burn(account, amount);
    }

    /// @notice  Burn rwa token
    /// @param   amount  the amount of token you want to burn
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
}
