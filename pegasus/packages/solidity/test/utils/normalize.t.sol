// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {MyERC20} from "src/mock/myERC20.sol";
import {Normalize} from "src/utils/normalize.sol";

contract TestNormalize is Test {
    function testTokenAmountToDecimals() public pure {
        uint256 tokenAmount = 100e6;
        uint8 tokenDecimals = 6;
        uint8 targetDecimals = 18;
        uint256 result = Normalize.tokenAmountToDecimals(tokenAmount, tokenDecimals, targetDecimals);
        assertEq(result, 100e18);
        tokenAmount = 100e12;
        tokenDecimals = 12;
        targetDecimals = 6;
        result = Normalize.tokenAmountToDecimals(tokenAmount, tokenDecimals, targetDecimals);
        assertEq(result, 100e6);
        tokenAmount = 1e6;
        tokenDecimals = 6;
        targetDecimals = 6;
        tokenDecimals = 6;
        result = Normalize.tokenAmountToDecimals(tokenAmount, tokenDecimals, targetDecimals);
        assertEq(result, 1e6);
    }

    function testTokenAmountToWad() public pure {
        uint256 tokenAmount = 100e6;
        uint8 tokenDecimals = 6;
        uint256 result = Normalize.tokenAmountToWad(tokenAmount, tokenDecimals);
        assertEq(result, 100e18);
        tokenAmount = 100e27;
        tokenDecimals = 27;
        result = Normalize.tokenAmountToWad(tokenAmount, tokenDecimals);
        assertEq(result, 100e18);
        tokenAmount = 100e18;
        tokenDecimals = 18;
        result = Normalize.tokenAmountToWad(tokenAmount, tokenDecimals);
        assertEq(result, 100e18);
    }

    function testTokenAmountToWad2() public {
        uint256 tokenAmount = 100e6;
        address erc20 = address(new MyERC20("USDC", "USDC", 6));
        (uint256 result, uint256 tokenDecimals) =
            Normalize.tokenAmountToWadWithTokenAddress(tokenAmount, erc20);
        assertEq(result, 100e18);
        assertEq(tokenDecimals, 6);
        tokenAmount = 100e27;
        erc20 = address(new MyERC20("USDC", "USDC", 27));

        (result, tokenDecimals) = Normalize.tokenAmountToWadWithTokenAddress(tokenAmount, erc20);
        assertEq(tokenDecimals, 27);
        assertEq(result, 100e18);
        tokenAmount = 100e18;
        erc20 = address(new MyERC20("USDC", "USDC", 18));
        (result, tokenDecimals) = Normalize.tokenAmountToWadWithTokenAddress(tokenAmount, erc20);
        assertEq(tokenDecimals, 18);
        assertEq(result, 100e18);
    }

    function testWadAmountByPrice() public pure {
        uint256 wadAmount = 100e18;
        uint256 wadPrice = 1e18;
        uint256 result = Normalize.wadAmountByPrice(wadAmount, wadPrice);
        assertEq(result, 100e18);

        wadAmount = 100e18;
        wadPrice = 1.1e18;
        result = Normalize.wadAmountByPrice(wadAmount, wadPrice);
        assertEq(result, 110e18);

        wadAmount = 100e18;
        wadPrice = 0.88e18;
        result = Normalize.wadAmountByPrice(wadAmount, wadPrice);
        assertEq(result, 88e18);
    }

    function testWadAmountToDecimals() public pure {
        uint256 wadAmount = 100e18;
        uint8 targetDecimals = 6;
        uint256 result = Normalize.wadAmountToDecimals(wadAmount, targetDecimals);
        assertEq(result, 100e6);

        targetDecimals = 18;
        result = Normalize.wadAmountToDecimals(wadAmount, targetDecimals);
        assertEq(result, 100e18);

        targetDecimals = 24;
        result = Normalize.wadAmountToDecimals(wadAmount, targetDecimals);
        assertEq(result, 100e24);
    }

    function testWadTokenAmountForWadPrice() public pure {
        uint256 wadAmount = 100e18;
        uint256 wadPrice = 1e18;
        uint256 result = Normalize.wadTokenAmountForPrice(wadAmount, wadPrice, 18);
        assertEq(result, 100e18);

        wadAmount = 110e18;
        wadPrice = 1.1e18;
        result = Normalize.wadTokenAmountForPrice(wadAmount, wadPrice, 6);
        assertEq(result, 100e6);

        wadAmount = 88e18;
        wadPrice = 0.88e18;
        result = Normalize.wadTokenAmountForPrice(wadAmount, wadPrice, 6);
        assertEq(result, 100e6);
    }
}
