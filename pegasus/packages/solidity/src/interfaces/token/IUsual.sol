// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IUsual is IERC20Metadata {
    /// @notice mint Usual token
    /// @dev Can only be called by USUAL_MINT role
    /// @param to address of the account who want to mint their token
    /// @param amount the amount of tokens to mint
    function mint(address to, uint256 amount) external;

    /// @notice burnFrom Usual token
    /// @dev Can only be called by USUAL_BURN role
    /// @param account address of the account who want to burn
    /// @param amount the amount of tokens to burn
    function burnFrom(address account, uint256 amount) external;

    /// @notice burn Usual token
    /// @dev Can only be called by USUAL_BURN role
    /// @param amount the amount of tokens to burn
    function burn(uint256 amount) external;

    /// @notice check if the account is blacklisted
    /// @param account address of the account to check
    /// @return bool
    function isBlacklisted(address account) external view returns (bool);
}
