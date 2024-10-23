// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {ICurveFactory} from "shared/interfaces/curve/ICurveFactory.sol";
import {ICurvePool} from "shared/interfaces/curve/ICurvePool.sol";
import {IGauge} from "src/interfaces/curve/IGauge.sol";
import {USDC} from "src/mock/constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TestScript} from "scripts/tests/Test.s.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

import {console} from "forge-std/console.sol";

/// @author  au2001
/// @title   Script to fund the Curve Pool
/// @dev     Used for debugging purposes

contract FundCurvePoolScript is TestScript {
    ICurveFactory constant STABLESWAP_NG_FACTORY =
        ICurveFactory(0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf);
    ICurvePool public curvePool;
    IGauge public gauge;

    function run() public override {
        super.run();

        vm.label(USDC, "USDC");

        curvePool = ICurvePool(STABLESWAP_NG_FACTORY.find_pool_for_coins(USDC, address(USD0)));
        require(address(curvePool) != address(0), "curve pool not deployed");
        vm.label(address(curvePool), "curvePool");

        gauge = IGauge(STABLESWAP_NG_FACTORY.get_gauge(address(curvePool)));
        require(address(gauge) != address(0), "curve gauge not deployed");
        vm.label(address(gauge), "gauge");

        require(gauge.manager() == usual, "wrong gauge manager");

        addUsd0RewardTokenToPool(420_000e18);

        depositLiquidity(alice, 200e18, "alice");
        depositLiquidity(bob, 200e18, "bob");

        for (uint256 i; i < 10; ++i) {
            (address account,) = deriveMnemonic(i + 7);
            depositLiquidity(account, 1000e18, Strings.toString(i));
        }

        claimRewards(alice, "alice");
        claimRewards(bob, "bob");

        for (uint256 i; i < 10; ++i) {
            (address account,) = deriveMnemonic(i + 7);
            claimRewards(account, Strings.toString(i));
        }
    }

    function addUsd0RewardTokenToPool(uint256 _amount) public {
        if (gauge.reward_data(address(USD0)).distributor != address(0)) {
            console.log("USD0 rewards already added");
            return;
        }

        _dealETH(usual);
        _dealUsd0(usual, _amount);

        vm.broadcast(usual);
        gauge.add_reward(address(USD0), usual);

        vm.startBroadcast(usual);
        USD0.approve(address(gauge), _amount);
        gauge.deposit_reward_token(address(USD0), _amount);
        vm.stopBroadcast();
    }

    function depositLiquidity(address _from, uint256 _amount, string memory _name)
        public
        returns (uint256 lpAmount)
    {
        lpAmount = gauge.balanceOf(_from);
        if (lpAmount != 0) {
            console.log(_from, "already has", lpAmount, gauge.symbol());
            return lpAmount;
        }

        address[] memory coins = STABLESWAP_NG_FACTORY.get_coins(address(curvePool));
        uint256[] memory amounts = new uint256[](coins.length);
        for (uint256 i; i < coins.length; ++i) {
            // Store the previous coin balances of the user
            amounts[i] = IERC20(coins[i]).balanceOf(_from);
        }

        _dealETH(_from);

        lpAmount = curvePool.balanceOf(_from);
        if (lpAmount == 0) {
            _dealUsd0(_from, _amount);
            _dealUSDC(_from, _amount / 1e12);

            vm.startBroadcast(_from);

            for (uint256 i; i < coins.length; ++i) {
                // Don't deposit the coin balances the user previously had
                amounts[i] = IERC20(coins[i]).balanceOf(_from) - amounts[i];
                require(amounts[i] != 0, "no coins to deposit");

                IERC20(coins[i]).approve(address(curvePool), amounts[i]);
            }

            lpAmount = curvePool.add_liquidity(amounts, 0);
            require(lpAmount != 0, "no lp tokens");
        } else {
            vm.startBroadcast(_from);
        }

        curvePool.approve(address(gauge), lpAmount);
        gauge.deposit(lpAmount);

        vm.stopBroadcast();

        console.log(_name, "deposited", lpAmount, curvePool.symbol());
    }

    function claimRewards(address _from, string memory _name) public {
        uint256 rewardCount = gauge.reward_count();
        IERC20Metadata[] memory tokens = new IERC20Metadata[](rewardCount);
        uint256[] memory balances = new uint256[](rewardCount);
        bool hasRewards = false;
        for (uint256 i; i < rewardCount; ++i) {
            tokens[i] = IERC20Metadata(gauge.reward_tokens(i));
            balances[i] = tokens[i].balanceOf(_from);

            hasRewards = hasRewards || gauge.claimable_reward(_from, address(tokens[i])) != 0;
        }

        if (!hasRewards) {
            console.log(_name, "has no reward yet");
            return;
        }

        _dealETH(_from);

        vm.broadcast(_from);
        gauge.claim_rewards();

        for (uint256 i; i < rewardCount; ++i) {
            uint256 claimedRewards = tokens[i].balanceOf(_from) - balances[i];
            console.log(_name, "claimed", claimedRewards, tokens[i].symbol());
        }
    }
}
