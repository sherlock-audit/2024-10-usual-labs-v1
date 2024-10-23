// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {RegistryAccess} from "src/registry/RegistryAccess.sol";
import {RegistryContract} from "src/registry/RegistryContract.sol";

import {L2Usd0} from "src/L2/token/L2Usd0.sol";
import {L2Usd0PP} from "src/L2/token/L2Usd0PP.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {ProxyAdmin} from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from
    "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {
    DEFAULT_ADMIN_ROLE,
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_USD0,
    CONTRACT_USD0PP,
    HEXAGATE_PAUSER,
    PAUSING_CONTRACTS_ROLE,
    USD0_BURN,
    USD0_MINT
} from "src/constants.sol";
import {USD0Symbol, USD0Name, USDPPSymbol, USDPPName} from "src/mock/constants.sol";

import {L2BaseScript} from "scripts/deployment/L2/L2Base.s.sol";

import {console} from "forge-std/console.sol";

contract L2ContractScript is L2BaseScript {
    function run() public virtual override {
        super.run();
        if (block.chainid != 42_161) {
            console.log("This script is only for arbitrum");
            return;
        }
        Options memory upgradeOptions;

        // Deploy Registry Access
        vm.startBroadcast(alicePrivateKey);
        console.log("msg.sender address:", msg.sender);
        registryAccess = RegistryAccess(
            Upgrades.deployTransparentProxy(
                "RegistryAccess.sol",
                usualProxyAdmin,
                abi.encodeCall(RegistryAccess.initialize, (alice)),
                upgradeOptions
            )
        );
        console.log("RegistryAccess address:", address(registryAccess));

        // Deploy Registry Contract
        registryContract = RegistryContract(
            Upgrades.deployTransparentProxy(
                "RegistryContract.sol",
                usualProxyAdmin,
                abi.encodeCall(RegistryContract.initialize, (address(registryAccess))),
                upgradeOptions
            )
        );
        console.log("RegistryContract address:", address(registryContract));
        // Setting up registryAccess contract
        registryContract.setContract(CONTRACT_REGISTRY_ACCESS, address(registryAccess));
        // Deploy USD0
        USD0 = L2Usd0(
            Upgrades.deployTransparentProxy(
                "L2Usd0.sol",
                usualProxyAdmin,
                abi.encodeCall(L2Usd0.initialize, (address(registryContract), USD0Name, USD0Symbol))
            )
        );
        registryContract.setContract(CONTRACT_USD0, address(USD0));

        //Deploy USD0PP
        USD0PP = L2Usd0PP(
            Upgrades.deployTransparentProxy(
                "L2Usd0PP.sol",
                usualProxyAdmin,
                abi.encodeCall(
                    L2Usd0PP.initialize, (address(registryContract), USDPPName, USDPPSymbol)
                )
            )
        );
        registryContract.setContract(CONTRACT_USD0PP, address(USD0PP));

        // Setup roles TODO WHEN OFT_MINT_BURN_ADAPTER_ARBITRUM is ready
        // registryAccess.grantRole(USD0_MINT, address(OFT_MINT_BURN_ADAPTER_ARBITRUM));
        // registryAccess.grantRole(USD0_BURN, address(OFT_MINT_BURN_ADAPTER_ARBITRUM));
        // registryAccess.grantRole(USD0PP_MINT, address(OFT_MINT_BURN_ADAPTER_ARBITRUM));
        // registryAccess.grantRole(USD0PP_BURN, address(OFT_MINT_BURN_ADAPTER_ARBITRUM));

        // Pausing set to hexagate
        registryAccess.grantRole(PAUSING_CONTRACTS_ROLE, HEXAGATE_PAUSER);

        // Hand over the ownership of the contracts to the multisig
        registryAccess.beginDefaultAdminTransfer(usual);
        vm.stopBroadcast();

        // Debug logs
        console.log("Usd0 address:", address(USD0));
        console.log("Usd0PP address:", address(USD0PP));
    }
}
