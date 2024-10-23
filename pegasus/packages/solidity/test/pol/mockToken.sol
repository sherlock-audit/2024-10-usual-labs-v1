// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockToken is ERC20Permit {
    constructor(string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
        ERC20Permit(name_)
    {}

    function setBalance(address to, uint256 amount) public {
        _burn(to, balanceOf(to));
        _mint(to, amount);
    }
}
