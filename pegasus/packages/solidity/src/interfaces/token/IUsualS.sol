// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IUsualS is IERC20Metadata {
    /// @notice burnFrom UsualS token
    /// @dev Can only be called by USUALS_BURN role
    /// @param account address of the account who want to burn
    /// @param amount the amount of tokens to burn
    function burnFrom(address account, uint256 amount) external;

    /// @notice burn UsualS token
    /// @dev Can only be called by USUALS_BURN role
    /// @param amount the amount of tokens to burn
    function burn(uint256 amount) external;

    /// @notice check if the account is blacklisted
    /// @param account address of the account to check
    /// @return bool True if the account is blacklisted
    function isBlacklisted(address account) external view returns (bool);

    /// @notice send total supply of UsualS tokens to staking contract
    /// @dev Can only be called by the staking contract (UsualSP contract)
    function stakeAll() external;
}
