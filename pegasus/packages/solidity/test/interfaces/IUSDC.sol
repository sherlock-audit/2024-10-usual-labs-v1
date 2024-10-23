// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IUSDC is IERC20Metadata {
    function mint(address to, uint256 amount) external;
    function masterMinter() external view returns (address);
    function configureMinter(address minter, uint256 minterAllowedAmount) external returns (bool);
    function blacklist(address _account) external;
    function blacklister() external view returns (address);
}
