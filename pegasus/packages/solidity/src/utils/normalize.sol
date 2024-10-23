// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {SCALAR_ONE} from "src/constants.sol";

/// @title Normalize decimals between tokens
library Normalize {
    /// @notice Normalize token amount to target decimals
    /// @notice i.e 100 USDC with 6 decimals to 100e18 USDC with 18 decimals
    /// @param tokenAmount The token amount
    /// @param tokenDecimals The token decimals
    /// @param targetDecimals The target decimals
    function tokenAmountToDecimals(uint256 tokenAmount, uint8 tokenDecimals, uint8 targetDecimals)
        internal
        pure
        returns (uint256)
    {
        if (tokenDecimals < targetDecimals) {
            return tokenAmount * (10 ** uint256(targetDecimals - tokenDecimals));
        } else if (tokenDecimals > targetDecimals) {
            return tokenAmount / (10 ** uint256(tokenDecimals - targetDecimals));
        } else {
            return tokenAmount;
        }
    }

    /// @notice Normalize token amount to 18 decimals
    /// @notice i.e 100 USDC with 6 decimals to 100e18 USDC with 18 decimals
    /// @param tokenAmount The token amount
    /// @param tokenDecimals The token decimals
    function tokenAmountToWad(uint256 tokenAmount, uint8 tokenDecimals)
        internal
        pure
        returns (uint256)
    {
        return tokenAmountToDecimals(tokenAmount, tokenDecimals, 18);
    }

    /// @notice Normalize token amount to wad
    /// @notice i.e 10e6 USYC with 6 decimals will result in wadAmount = 10e18 and  tokenDecimals = 6
    /// @param token The token address
    /// @param tokenAmount The token amount
    /// @return wadAmount The normalized token amount in wad
    /// @return tokenDecimals The token decimals
    function tokenAmountToWadWithTokenAddress(uint256 tokenAmount, address token)
        internal
        view
        returns (uint256, uint8)
    {
        uint8 tokenDecimals = uint8(IERC20Metadata(token).decimals());
        uint256 wadAmount = tokenAmountToWad(tokenAmount, uint8(tokenDecimals));
        return (wadAmount, tokenDecimals);
    }

    /// @notice Returns wad amount of token at wad price.
    /// @notice i.e 10e6 USYC with 6 decimals will be wadAmount = 10e18
    /// @notice if wadPrice is 1e18 USD then 10e18 USD0 will be worth 10e18 USD
    /// @param wadAmount The wad amount (18 decimals)
    /// @param wadPrice The wad price (18 decimals)
    /// @return The normalized token amount for price
    function wadAmountByPrice(uint256 wadAmount, uint256 wadPrice)
        internal
        pure
        returns (uint256)
    {
        return Math.mulDiv(wadAmount, wadPrice, SCALAR_ONE, Math.Rounding.Floor);
    }

    /// @notice return how much token we can have for stable amount.
    /// @notice i.e 10 (10e18) USD0 with 18 decimals worth 2$ each (2e18) will return 5e6 USYC with 6 decimals
    /// @param wadStableAmount The wad stable token amount
    /// @param wadPrice The wad price with for the token in stable
    /// @param tokenDecimals The token decimals
    /// @return The token amount for price with token decimals
    function wadTokenAmountForPrice(uint256 wadStableAmount, uint256 wadPrice, uint8 tokenDecimals)
        internal
        pure
        returns (uint256)
    {
        return Math.mulDiv(wadStableAmount, 10 ** tokenDecimals, wadPrice, Math.Rounding.Floor);
    }

    /// @dev Converts a WAD amount to a different number of decimals.
    /// @param wadAmount The WAD amount to convert.
    /// @param targetDecimals The number of decimals to convert to.
    /// @return The converted amount with the target number of decimals.
    function wadAmountToDecimals(uint256 wadAmount, uint8 targetDecimals)
        internal
        pure
        returns (uint256)
    {
        return tokenAmountToDecimals(wadAmount, 18, targetDecimals);
    }
}
