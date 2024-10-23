// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import "forge-std/Script.sol";
import {USYC} from "src/mock/constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {TestScript} from "scripts/tests/Test.s.sol";

// solhint-disable-next-line no-console

contract FundAccountWithUSYCScript is TestScript {
    uint256 amount = 10_000_000e6;

    function run() public virtual override {
        super.run();

        _dealUSYC(alice, amount);
        _dealUSYC(bob, amount);

        console.log("### USYC balance Of alice", IERC20(USYC).balanceOf(alice));
        console.log("### USYC balance Of bob", IERC20(USYC).balanceOf(bob));
    }
}
