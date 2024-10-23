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

contract FundAccountWithUsd0Script is TestScript {
    function run() public override {
        super.run();

        vm.label(USYC, "USYC");

        swapCollateral(alice, 200_000e6, "alice");
        swapCollateral(bob, 200_000e6, "bob");

        for (uint256 i; i < 10; ++i) {
            (address account,) = deriveMnemonic(i + 5);
            swapCollateral(account, 1_000_000e6, Strings.toString(i));
        }
    }

    function swapCollateral(address _from, uint256 _amount, string memory _name) public {
        _dealETH(_from);
        _dealUSYC(_from, _amount);

        vm.startBroadcast(_from);
        IUSYC(USYC).approve(address(daoCollateral), _amount);
        daoCollateral.swap(USYC, _amount, 0);
        vm.stopBroadcast();

        console.log(_name, "minted", _amount, IUSYC(USYC).symbol());
    }
}
