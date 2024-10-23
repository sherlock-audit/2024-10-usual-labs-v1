// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IUSYC is IERC20Metadata {
    function setMinterAllowance(address to, uint256 amount) external;
    function owner() external returns (address);
    function authority() external returns (address);
    function mint(address to, uint256 amount) external;
    function blacklist(address _account) external;
    function blacklister() external view returns (address);
}
