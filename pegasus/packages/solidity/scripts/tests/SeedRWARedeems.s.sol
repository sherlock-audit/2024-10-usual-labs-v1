// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {USYC} from "src/mock/constants.sol";
import {TestScript} from "scripts/tests/Test.s.sol";
import {IUSYC} from "test/interfaces/IUSYC.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

import {console} from "forge-std/console.sol";

/// @author  au2001
/// @title   Script to create some Usd0 supply by swapping RWA
/// @dev     Used for debugging purposes

contract SeedRWARedeemsScript is TestScript {
    function run() public override {
        super.run();

        vm.label(USYC, "USYC");

        vm.broadcast(treasury);
        IUSYC(USYC).approve(address(daoCollateral), type(uint256).max);

        redeemRWA(alice, 200e18, "alice");
        redeemRWA(bob, 200e18, "bob");

        for (uint256 i; i < 10; ++i) {
            (address account,) = deriveMnemonic(i + 5);
            redeemRWA(account, 1000e18, Strings.toString(i));
        }
    }

    function redeemRWA(address _from, uint256 _amount, string memory _name) public {
        uint256 balance = IUSYC(USYC).balanceOf(_from);

        _dealETH(_from);
        _dealUsd0(_from, _amount);

        vm.startBroadcast(_from);
        USD0.approve(address(daoCollateral), _amount);
        daoCollateral.redeem(USYC, _amount, 0);
        vm.stopBroadcast();

        uint256 rwaAmount = IUSYC(USYC).balanceOf(_from) - balance;
        console.log(_name, "redeemed", rwaAmount, IUSYC(USYC).symbol());
    }
}
