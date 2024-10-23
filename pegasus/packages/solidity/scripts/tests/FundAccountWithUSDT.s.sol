// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import "forge-std/Script.sol";
import {USDT} from "src/mock/constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {TestScript} from "scripts/tests/Test.s.sol";

// needed to avoid revert on USDT transfer because
// USDT transfer function does not return any boolean if successful or not.
interface IUSDT {
    function transfer(address to, uint256 amount) external;
}

contract FundAccountWithUSDTScript is TestScript {
    // If this break, another address can be found here => https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7#balances
    address tetherTreasury = 0x5754284f345afc66a98fbB0a0Afe71e0F007B949;
    uint256 amount = 10_000_000e6;

    function run() public virtual override {
        super.run();
        console.log("### USDT balance Of tether treasury", IERC20(USDT).balanceOf(tetherTreasury));
        _dealUSDT(alice, amount);
        _dealUSDT(bob, amount);

        console.log("### USDT balance Of alice", IERC20(USDT).balanceOf(alice));
        console.log("### USDT balance Of bob", IERC20(USDT).balanceOf(bob));
    }

    function _dealUSDT(address _to, uint256 _amount) internal {
        vm.broadcast(tetherTreasury);
        IUSDT(USDT).transfer(_to, _amount);
    }
}
