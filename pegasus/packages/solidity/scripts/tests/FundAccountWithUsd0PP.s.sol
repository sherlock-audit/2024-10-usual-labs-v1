// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IUsd0PP} from "src/interfaces/token/IUsd0PP.sol";
import {CONTRACT_USD0PP} from "src/constants.sol";
import {TestScript} from "scripts/tests/Test.s.sol";

import {console} from "forge-std/console.sol";

/// @author  au2001
/// @title   Script to lock USD0 into USD0++
/// @dev     Used for debugging purposes

contract FundAccountWithUsd0PPScript is TestScript {
    IUsd0PP public usd0PP;

    function run() public override {
        super.run();

        usd0PP = IUsd0PP(registryContract.getContract(CONTRACT_USD0PP));

        vm.label(address(usd0PP), "usd0PP");

        depositTokens(alice, 200e18);
        depositTokens(bob, 200e18);

        for (uint256 i; i < 10; ++i) {
            (address account,) = deriveMnemonic(i + 5);
            depositTokens(account, 1000e18);
        }

        for (uint256 i; i < 10; ++i) {
            (address account,) = deriveMnemonic(i + 5);
            (address recipient,) = deriveMnemonic(i + 6);
            transferUsd0PP(account, recipient, 500e18);
        }
    }

    function depositTokens(address _from, uint256 _amount) public {
        _dealETH(_from);
        _dealUsd0(_from, _amount);

        vm.startBroadcast(_from);
        USD0.approve(address(usd0PP), _amount);
        usd0PP.mint(_amount);
        vm.stopBroadcast();

        console.log(_from, "deposited", _amount, usd0PP.symbol());
    }

    function transferUsd0PP(address _from, address _to, uint256 _amount) public {
        _dealETH(_from);

        vm.startBroadcast(_from);
        usd0PP.transfer(_to, _amount);
        vm.stopBroadcast();

        console.log(_from, "sent", _amount, usd0PP.symbol());
    }
}
