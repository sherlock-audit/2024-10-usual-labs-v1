// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import "forge-std/Script.sol";

import {TestScript} from "scripts/tests/Test.s.sol";

contract WhitelistUSYCScript is TestScript {
    function run() public virtual override {
        super.run();

        // we need to whitelist the users
        _whitelistUSYC(alice);
        _whitelistUSYC(bob);
        _whitelistUSYC(treasury);
    }
}
