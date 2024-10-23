// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ICurveFactory} from "shared/interfaces/curve/ICurveFactory.sol";
import {
    DAO_COLLATERAL,
    USUALSP,
    SWAPPER_ENGINE,
    USD0_BURN,
    USD0_MINT,
    USUAL_BURN
} from "src/constants.sol";
import {
    USDC_PRICE_FEED_MAINNET,
    USDC,
    USDT_PRICE_FEED_MAINNET,
    USDT,
    USD0Symbol,
    USYC_PRICE_FEED_MAINNET,
    USYC
} from "src/mock/constants.sol";
import {ContractScript} from "scripts/deployment/Contracts.s.sol";

import {console} from "forge-std/console.sol";

// solhint-disable-next-line no-console
contract FinalConfigScript is ContractScript {
    address public curvePool;
    address public gauge;

    function run() public virtual override {
        super.run();

        vm.startBroadcast(usualPrivateKey);

        // add roles
        registryAccess.grantRole(DAO_COLLATERAL, address(daoCollateral));
        registryAccess.grantRole(USUALSP, address(usualSP));
        registryAccess.grantRole(USD0_MINT, address(daoCollateral));
        registryAccess.grantRole(USD0_BURN, address(daoCollateral));
        registryAccess.grantRole(SWAPPER_ENGINE, address(swapperEngine));

        console.log("daoCollateral address:", address(daoCollateral));
        vm.label(USYC, "USYC");
        vm.label(USDT, "USDT");
        vm.label(USDC, "USDC");
        // add rwa to registry if it is not already added
        if (!tokenMapping.isUsd0Collateral(USYC)) {
            tokenMapping.addUsd0Rwa(USYC);
        }

        console.log("Rwa token address:", USYC);
        console.log("registryContract address:", address(registryContract));
        console.log("registryAccess address:", address(registryAccess));

        // add external price feed

        classicalOracle.initializeTokenOracle(
            USDC, address(USDC_PRICE_FEED_MAINNET), 1 days + 600, true
        );
        classicalOracle.initializeTokenOracle(
            USDT, address(USDT_PRICE_FEED_MAINNET), 1 days + 600, true
        );
        classicalOracle.initializeTokenOracle(USYC, address(USYC_PRICE_FEED_MAINNET), 4 days, false);

        dataPublisher.addWhitelistPublisher(address(USD0), usual);

        vm.stopBroadcast();

        // treasury allow max uint256 to daoCollateral
        vm.startBroadcast(treasuryPrivateKey);
        IERC20(USYC).approve(address(daoCollateral), type(uint256).max);
        vm.stopBroadcast();

        // init the oracle prices
        _initOracle();
        uint256 price = classicalOracle.getPrice(USYC);
        console.log("rwa:%s price:%s", USYC, uint256(price));
        console.log("USD0:%s price:%s", address(USD0), usualOracle.getQuote(address(USD0), 1e18));
        _deployCurvePool();
    }

    function _initOracle() internal {
        vm.startBroadcast(usualPrivateKey);
        // mandatory to have a working oracle
        dataPublisher.publishData(address(USD0), 1e18);
        dataPublisher.publishData(address(USD0), 1e18);
        usualOracle.initializeTokenOracle(address(USD0), 1 days, true);
        vm.stopBroadcast();
    }

    // Deploy Curve plain pool and gauge
    function _deployCurvePool() public {
        address STABLESWAP_NG_FACTORY = 0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf;
        vm.startBroadcast(usualPrivateKey);
        // deploy curve pool
        address[] memory tokens = new address[](2);
        uint8[] memory asset_types = new uint8[](2);
        bytes4[] memory method_ids = new bytes4[](2);
        address[] memory oracles = new address[](2);
        tokens[0] = USDC;
        tokens[1] = address(USD0);
        curvePool = ICurveFactory(STABLESWAP_NG_FACTORY).deploy_plain_pool(
            string(abi.encodePacked(USD0Symbol, "/USDC")),
            string(abi.encodePacked(USD0Symbol, "-USDC")),
            tokens,
            200, //A
            4_000_000, //fee
            20_000_000_000, // offpeg fee multiplier
            866, // ma exp time
            0, // implementation idx
            asset_types, // asset types
            method_ids, // method ids
            oracles // oracles
        );
        gauge = ICurveFactory(STABLESWAP_NG_FACTORY).deploy_gauge(curvePool);
        // Print curvePool and gauge address
        console.log("curvePool address:", curvePool);
        console.log("gauge address:", gauge);
        vm.stopBroadcast();
    }
}
