// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {Usd0PP} from "src/token/Usd0PP.sol";
import {Id, IMorpho, MarketParams, Position} from "shared/interfaces/morpho/IMorpho.sol";
import {MarketParamsLib} from "shared/MarketParamsLib.sol";
import {
    USDC,
    USYC,
    MORPHO_MAINNET,
    ADAPTIVE_CURVE_IRM,
    SCALAR_ONE_SZABO
} from "src/mock/constants.sol";
import {CONTRACT_USD0PP} from "src/constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {TestScript} from "scripts/tests/Test.s.sol";

import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

/// @author  UsualTeam
/// @title   Script to fund the Morpho Pool
/// @dev     Used for debugging purposes

contract FundMorphoPoolScript is TestScript {
    using MarketParamsLib for MarketParams;

    IMorpho morpho = IMorpho(MORPHO_MAINNET);
    // based on https://etherscan.io/tx/0xd0c4f8e58c0ece3d576b846e30745f08cc5faa2ef80455e1226e990c9988b6c6#eventlog
    uint256 constant lltv = 860_000_000_000_000_000;
    address constant MorphoChainlinkToUSDCPrice = 0x3A72F1F8e549C2398c83Fb223c178162bac2bdC3;
    Id id;
    address usd0PP;

    function run() public override {
        super.run();

        vm.label(USDC, "USDC");
        usd0PP = registryContract.getContract(CONTRACT_USD0PP);
        MarketParams memory market = createMarket();
        // supply 1M$ each side
        supplyUSDCAssetToMarket(market, alice, SCALAR_ONE_SZABO);
        supplyUsd0PPCollateralToMarket(market, alice, SCALAR_ONE_SZABO);
    }

    function createMarket() public returns (MarketParams memory market) {
        market = MarketParams({
            loanToken: USDC,
            collateralToken: usd0PP,
            oracle: MorphoChainlinkToUSDCPrice,
            irm: ADAPTIVE_CURVE_IRM,
            lltv: lltv
        });
        id = market.id();
        vm.startBroadcast();
        morpho.createMarket(market);
        vm.stopBroadcast();
    }

    function supplyUSDCAssetToMarket(
        MarketParams memory marketParams,
        address _from,
        uint256 amount
    ) public {
        // mint USDC
        _dealUSDC(_from, amount);
        // empty data
        bytes memory data = "";
        // allow usdc
        vm.startBroadcast(_from);
        IERC20(USDC).approve(MORPHO_MAINNET, amount);
        // supply usdC to the market
        morpho.supply(marketParams, amount, 0, _from, data);
        vm.stopBroadcast();
    }

    function supplyUsd0PPCollateralToMarket(
        MarketParams memory marketParams,
        address _from,
        uint256 amountUsd0PP
    ) public {
        // deal USD0
        _dealUsd0(_from, amountUsd0PP);
        // empty data
        bytes memory data = "";
        // mint USD0
        vm.broadcast(usual);
        registryAccess.grantRole(keccak256("ALLOWLISTED"), _from);
        Usd0PP usdpp = Usd0PP(usd0PP);
        // approve to mint usd0PP
        vm.startBroadcast(_from);
        IERC20(address(USD0)).approve(address(usd0PP), amountUsd0PP);
        usdpp.mint(amountUsd0PP);
        // allow usdc
        IERC20(usd0PP).approve(MORPHO_MAINNET, amountUsd0PP);
        // supply usdC to the market
        morpho.supplyCollateral(marketParams, amountUsd0PP, _from, data);
        vm.stopBroadcast();
    }
}
