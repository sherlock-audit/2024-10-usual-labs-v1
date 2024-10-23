// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {ICurveFactory} from "shared/interfaces/curve/ICurveFactory.sol";
import {ICurvePool} from "shared/interfaces/curve/ICurvePool.sol";
import {USDC} from "src/mock/constants.sol";
import {TestScript} from "scripts/tests/Test.s.sol";
import {IUSDC} from "test/interfaces/IUSDC.sol";

import {console} from "forge-std/console.sol";

/// @author  au2001
/// @title   Script to execute swaps on Curve
/// @dev     Used for debugging purposes
/// @dev     Requires running the FundCurvePool script beforehand

contract SeedCurveSwapsScript is TestScript {
    ICurveFactory constant STABLESWAP_NG_FACTORY =
        ICurveFactory(0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf);

    ICurvePool public curvePool;

    function run() public override {
        super.run();

        vm.label(USDC, "USDC");

        curvePool = ICurvePool(STABLESWAP_NG_FACTORY.find_pool_for_coins(USDC, address(USD0)));
        require(address(curvePool) != address(0), "curve pool not deployed");
        vm.label(address(curvePool), "curvePool");

        swapUSDC(alice, 200e6);
        swapUSDC(bob, 200e6);

        swapUsd0(alice, 200e18);
        swapUsd0(bob, 200e18);

        for (uint256 i; i < 10; ++i) {
            (address account,) = deriveMnemonic(i + 7);
            swapUSDC(account, 200e6);
            swapUsd0(account, 1000e18);
        }
    }

    function swapUSDC(address _from, uint256 _amount) public {
        _dealETH(_from);
        _dealUSDC(_from, _amount);

        bool stbcFirst = curvePool.coins(0) == address(USD0);

        uint256 stbcAmount;

        vm.startBroadcast(_from);
        IUSDC(USDC).approve(address(curvePool), _amount);
        if (stbcFirst) stbcAmount = curvePool.exchange(1, 0, _amount, 0, _from);
        else stbcAmount = curvePool.exchange(0, 1, _amount, 0, _from);
        vm.stopBroadcast();

        console.log(_from, "swapped", stbcAmount, USD0.symbol());
    }

    function swapUsd0(address _from, uint256 _amount) public {
        _dealETH(_from);
        _dealUsd0(_from, _amount);

        bool stbcFirst = curvePool.coins(0) == address(USD0);

        uint256 usdcAmount;

        vm.startBroadcast(_from);
        USD0.approve(address(curvePool), _amount);
        if (stbcFirst) usdcAmount = curvePool.exchange(0, 1, _amount, 0, _from);
        else usdcAmount = curvePool.exchange(1, 0, _amount, 0, _from);
        vm.stopBroadcast();

        console.log(_from, "swapped", usdcAmount, IUSDC(USDC).symbol());
    }
}
