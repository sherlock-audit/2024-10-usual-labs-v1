// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {USYC, USDC} from "src/mock/constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {ICurveFactory} from "shared/interfaces/curve/ICurveFactory.sol";
import {ICurvePool} from "shared/interfaces/curve/ICurvePool.sol";
import {IGauge} from "src/interfaces/curve/IGauge.sol";
import {BaseDeploymentTest} from "test/deployment/baseDeployment.t.sol";

/// @author  Usual Tech Team
/// @title   Curve Deployment Script
/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting

contract CurveTest is BaseDeploymentTest {
    function setUp() public override {
        super.setUp();

        _mintUSYC(100 ether);
        deal(USYC, treasury, type(uint128).max);
    }

    function testCurveStablePoolAndGaugeShouldWork() public {
        // deploy a curve metapool
        assertEq(address(deploy.USD0()), address(USD0));
        address[] memory tokens = new address[](2);
        uint8[] memory asset_types = new uint8[](2);
        bytes4[] memory method_ids = new bytes4[](2);
        address[] memory oracles = new address[](2);
        tokens[0] = USDC;
        tokens[1] = address(USD0);
        vm.prank(alice);
        curvePool = ICurveFactory(STABLESWAP_NG_FACTORY).deploy_plain_pool(
            "USD0/USDC",
            "USD0-USDC",
            tokens,
            200, //A
            4_000_000, //fee
            20_000_000_000, // offpeg fee multiplier
            866, // ma exp time
            0, // implementation idx
            asset_types, // asset types
            method_ids, // method ids
            oracles // oracles
        );
        vm.prank(alice);
        gauge = ICurveFactory(STABLESWAP_NG_FACTORY).deploy_gauge(curvePool);
        vm.label(gauge, "gauge");
        //When a gauge is deployed via the Factory, the deployer (msg.sender) is automatically set as the gauge manager.
        // This address can call the add_rewards function within the OwnerProxy to add both reward tokens and distributors.
        // To deposit reward tokens, the distributor must call the deposit_reward_token function within the specific gauge.

        vm.label(curvePool, "curvePool");
        vm.label(USDC, "USDC");
    }

    function testAddUsd0RewardTokenToPoolShouldWork() public {
        testCurveStablePoolAndGaugeShouldWork();
        address manager = IGauge(gauge).manager();
        vm.prank(manager);
        // only alice can deposit reward token
        IGauge(gauge).add_reward(address(USD0), alice);
        vm.prank(address(daoCollateral));
        USD0.mint(alice, 420_000e18);
        vm.prank(alice);
        USD0.approve(gauge, type(uint256).max);
        vm.prank(alice);
        IGauge(gauge).deposit_reward_token(address(USD0), 420_000e18);
        assertEq(USD0.balanceOf(address(alice)), 0);
        assertEq(USD0.balanceOf(address(this)), 0);
    }

    function testLiquidityProviderShouldGetUsd0RewardByDepositingIntoGauge() public {
        testAddUsd0RewardTokenToPoolShouldWork();

        vm.prank(address(daoCollateral));
        USD0.mint(address(this), 200e18);
        assertEq(USD0.balanceOf(address(this)), 200e18);
        _dealUSDC(address(this), 200e6);
        assertEq(IERC20(USDC).balanceOf(address(this)), 200e6);
        USD0.approve(curvePool, type(uint256).max);
        IERC20(USDC).approve(curvePool, type(uint256).max);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 200e6;
        amounts[1] = 200e18;
        uint256 lpAmount = ICurvePool(curvePool).add_liquidity(amounts, 0);
        IERC20(curvePool).approve(gauge, type(uint256).max);
        IGauge(gauge).deposit(lpAmount);

        // 1 year later
        skip(365 days);
        IGauge(gauge).claim_rewards();
        assertApproxEqRel(USD0.balanceOf(address(this)), 420_000e18, 1e10);
    }
}
