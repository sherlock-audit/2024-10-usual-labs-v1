// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {
    USDC,
    USD0PP_MAINNET,
    MORPHO_MAINNET,
    MORPHO_CHAINLINK_ORACLE_USDC_SDAI,
    ADAPTIVE_CURVE_IRM
} from "src/mock/constants.sol";
import {Id, IMorpho, MarketParams} from "shared/interfaces/morpho/IMorpho.sol";
import {MarketParamsLib} from "shared/MarketParamsLib.sol";
import {BaseScript} from "scripts/deployment/Base.s.sol";

import {console} from "forge-std/console.sol";

contract MorphoMarket is BaseScript {
    using MarketParamsLib for MarketParams;

    function run() public override {
        super.run();
        // Check that the script is running on the correct chain
        if (block.chainid != 1) {
            console.log("Invalid chain");
            return;
        }

        vm.startBroadcast();
        uint256 lltv = 980_000_000_000_000_000;
        IMorpho morpho = IMorpho(MORPHO_MAINNET);
        // TODO REPLACE ORACLE WITH A PROPER ORACLE FOR USD0PP
        MarketParams memory marketParams = MarketParams({
            loanToken: USDC,
            collateralToken: USD0PP_MAINNET,
            oracle: MORPHO_CHAINLINK_ORACLE_USDC_SDAI,
            irm: ADAPTIVE_CURVE_IRM,
            lltv: lltv
        });
        Id id = marketParams.id();
        console.logBytes32(Id.unwrap(id));
        morpho.createMarket(marketParams);

        vm.stopBroadcast();
    }
}
