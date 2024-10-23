// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {RegistryContract} from "src/registry/RegistryContract.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {AirdropTaxCollector} from "src/airdrop/AirdropTaxCollector.sol";
import {AirdropDistribution} from "src/airdrop/AirdropDistribution.sol";
import {DistributionModule} from "src/distribution/DistributionModule.sol";
import {Usd0} from "src/token/Usd0.sol";
import {Usual} from "src/token/Usual.sol";
import {UsualX} from "src/vaults/UsualX.sol";
import {UsualSP} from "src/token/UsualSP.sol";
import {UsualS} from "src/token/UsualS.sol";
import {Usd0PP} from "src/token/Usd0PP.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

import {
    CONTRACT_USD0PP,
    CONTRACT_USUALS,
    CONTRACT_USUALSP,
    CONTRACT_SWAPPER_ENGINE,
    CONTRACT_USUAL,
    CONTRACT_DAO_COLLATERAL,
    CONTRACT_USD0,
    CONTRACT_USUAL,
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_TOKEN_MAPPING,
    CONTRACT_ORACLE,
    CONTRACT_USUALX,
    CONTRACT_AIRDROP_TAX_COLLECTOR,
    CONTRACT_AIRDROP_DISTRIBUTION,
    CONTRACT_DISTRIBUTION_MODULE,
    CONTRACT_USUALS,
    USUALS_BURN,
    USUAL_MINT,
    USUAL_BURN,
    RATE0,
    USUALSName,
    USUALSSymbol,
    USUALName,
    USUALSymbol,
    USUALXName,
    USUALXSymbol,
    USUALX_WITHDRAW_FEE,
    USUALSP_VESTING_STARTING_DATE,
    VESTING_DURATION_THREE_YEARS,
    REGISTRY_CONTRACT_MAINNET,
    USUAL_MULTISIG_MAINNET
} from "src/constants.sol";

import {console} from "forge-std/console.sol";
import {UpgradeScriptBase} from "scripts/deployment/utils/UpgradeScriptBase.sol";

// solhint-disable-next-line no-console
contract P10 is UpgradeScriptBase {
    function run() public {
        if (block.chainid == 1) {
            RegistryContractProxy = RegistryContract(REGISTRY_CONTRACT_MAINNET);
        } else {
            console.log("Invalid chain");
            return;
        }
        console.log("RegistryContractProxy : %s \n", address(RegistryContractProxy));
        // Upgrade Usd0 using V2
        DeployImplementationAndLogs(
            "Usd0.sol", CONTRACT_USD0, abi.encodeWithSelector(Usd0.initializeV2.selector)
        );
        // upgrade Usd0++ using V1
        DeployImplementationAndLogs(
            "Usd0PP.sol", CONTRACT_USD0PP, abi.encodeWithSelector(Usd0PP.initializeV1.selector)
        );

        // Deploy Usual token
        DeployNewProxyWithImplementationAndLogsOrFail(
            "Usual.sol",
            CONTRACT_USUAL,
            abi.encodeWithSelector(
                Usual.initialize.selector, address(RegistryContractProxy), USUALName, USUALSymbol
            )
        );

        // Deploy UsualS token
        DeployNewProxyWithImplementationAndLogsOrFail(
            "UsualS.sol",
            CONTRACT_USUALS,
            abi.encodeWithSelector(
                UsualS.initialize.selector, address(RegistryContractProxy), USUALSName, USUALSSymbol
            )
        );
    }
}

contract P11 is UpgradeScriptBase {
    function run() public {
        if (block.chainid == 1) {
            RegistryContractProxy = RegistryContract(REGISTRY_CONTRACT_MAINNET);
        } else {
            console.log("Invalid chain");
            return;
        }
        // Deploy UsualX token
        DeployNewProxyWithImplementationAndLogsOrFail(
            "UsualX.sol",
            CONTRACT_USUALX,
            abi.encodeWithSelector(
                UsualX.initialize.selector,
                address(RegistryContractProxy),
                USUALX_WITHDRAW_FEE,
                USUALXName,
                USUALXSymbol
            )
        );

        DeployNewProxyWithImplementationAndLogsOrFail(
            "UsualSP.sol",
            CONTRACT_USUALSP,
            abi.encodeWithSelector(
                UsualSP.initialize.selector,
                address(RegistryContractProxy),
                USUALSP_VESTING_STARTING_DATE,
                VESTING_DURATION_THREE_YEARS
            )
        );
    }
}

contract P12 is UpgradeScriptBase {
    function run() public {
        if (block.chainid == 1) {
            RegistryContractProxy = RegistryContract(REGISTRY_CONTRACT_MAINNET);
        } else {
            console.log("Invalid chain");
            return;
        }
        // DistributionModule
        DeployNewProxyWithImplementationAndLogsOrFail(
            "DistributionModule.sol",
            CONTRACT_DISTRIBUTION_MODULE,
            abi.encodeWithSelector(
                DistributionModule.initialize.selector,
                IRegistryContract(RegistryContractProxy),
                RATE0
            )
        );

        // AirDropTaxCollector
        DeployNewProxyWithImplementationAndLogsOrFail(
            "AirdropTaxCollector.sol",
            CONTRACT_AIRDROP_TAX_COLLECTOR,
            abi.encodeWithSelector(
                AirdropTaxCollector.initialize.selector, (address(RegistryContractProxy))
            )
        );
    }
}

contract P13 is UpgradeScriptBase {
    function run() public {
        if (block.chainid == 1) {
            RegistryContractProxy = RegistryContract(REGISTRY_CONTRACT_MAINNET);
        } else {
            console.log("Invalid chain");
            return;
        }

        // AirDropDistribution
        DeployNewProxyWithImplementationAndLogsOrFail(
            "AirdropDistribution.sol",
            CONTRACT_AIRDROP_DISTRIBUTION,
            abi.encodeWithSelector(
                AirdropDistribution.initialize.selector, (address(RegistryContractProxy))
            )
        );
    }
}
