// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {USDC} from "src/mock/constants.sol";

import {TestScript} from "scripts/tests/Test.s.sol";

// solhint-disable-next-line no-console
contract FundAccountWithUSDCScript is TestScript {
    // USDC worker and controller set here https://etherscan.io/tx/0x906c2014a1b4acb11a3af6497f10e2980f8ced09108ad264371fe05b30e976c9
    address worker = 0x5B6122C109B78C6755486966148C1D70a50A47D7;
    address controller = 0x79E0946e1C186E745f1352d7C21AB04700C99F71;
    address masterMinter = 0xE982615d461DD5cD06575BbeA87624fda4e3de17;
    uint256 amount = 10_000_000e6;

    function run() public virtual override {
        super.run();
        _dealUSDC(alice, amount);
        _dealUSDC(bob, amount);
        console.log("### USDC balance Of alice", IERC20(USDC).balanceOf(alice));
        console.log("### USDC balance Of bob", IERC20(USDC).balanceOf(bob));
    }
}
