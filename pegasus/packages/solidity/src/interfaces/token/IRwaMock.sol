// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IRwaMock is IERC20Metadata {
    function mint(address to, uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;

    function burn(uint256 amount) external;
}
