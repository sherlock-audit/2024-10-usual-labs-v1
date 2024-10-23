// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {USYC} from "src/mock/constants.sol";

import {BaseDeploymentTest} from "test/deployment/baseDeployment.t.sol";

/// @author  Usual Tech Team
/// @title   HashNote as a RWA Deployment Script
/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting

contract HashNoteTest is BaseDeploymentTest {
    function setUp() public override {
        super.setUp();
        _whitelistPublisher();
    }

    function testRWASwap(uint256 amount) public {
        amount = bound(amount, 100e6, type(uint128).max - 1);
        _mintUSYC(amount);
        vm.prank(alice);
        deal(USYC, alice, amount);
        assertEq(rwa.balanceOf(alice), amount);
        assertEq(USD0.balanceOf(alice), 0);
        uint256 rwaPrice = classicalOracle.getPrice(address(rwa));
        assertGt(rwaPrice, 1e18);
        assertEq(usualOracle.getPrice(address(USD0)), 1e18);
        vm.prank(alice);
        rwa.approve(address(daoCollateral), amount);
        uint256 amountInUsd = amount * rwaPrice / 1e6;
        vm.prank(alice);
        daoCollateral.swap(address(rwa), amount, amountInUsd);
        // 100 USYC = 100e6 => 100 USD0 = 100e18

        assertEq(USD0.balanceOf(alice), amountInUsd);
        // RWA token is now on bucket and not on dao Collateral
        assertEq(rwa.balanceOf(address(daoCollateral)), 0);
        assertEq(rwa.balanceOf(treasury), amount);
        assertEq(rwa.balanceOf(alice), 0);
    }

    function testRedeemFiat(uint256 amount) public {
        amount = bound(amount, 100e6, type(uint128).max - 1);
        testRWASwap(amount);
        uint256 treasuryRwaAmount = rwa.balanceOf(treasury);
        console.log("Treasury RWA amount: ", treasuryRwaAmount);
        assertEq(treasuryRwaAmount, amount);
        uint256 rwaPrice = classicalOracle.getPrice(address(rwa));

        uint256 usd0Amount = USD0.balanceOf(alice);
        uint256 amountInRWA = usd0Amount * 1e6 / rwaPrice;
        deal(USYC, treasury, usd0Amount);
        vm.prank(alice);
        daoCollateral.redeem(address(rwa), usd0Amount, 0);

        // The formula to calculate the amount of RWA that the user should get by redeeming STBC should be:
        // amountStableCoin * rwaDecimals * oracleDecimals / oraclePrice / stableCoinDecimals
        // And oracleDecimals = stableCoinDecimals = 18 so they cancel each other

        assertEq(USD0.balanceOf(alice), 0);
        uint256 fee = amountInRWA * 100 / 100_000; // 0.1%
        assertApproxEqRel(rwa.balanceOf(alice), amountInRWA - fee, 2e13);
    }
}
