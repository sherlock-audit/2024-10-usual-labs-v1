// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";

import {L2Usd0} from "src/L2/token/L2Usd0.sol";
import {L2Usd0PP} from "src/L2/token/L2Usd0PP.sol";

import {RegistryAccess} from "src/registry/RegistryAccess.sol";
import {RegistryContract} from "src/registry/RegistryContract.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {USD0Symbol, USD0Name, USDPPSymbol, USDPPName} from "src/mock/constants.sol";

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

import {console} from "forge-std/console.sol";

// solhint-disable-next-line no-console
contract Arbitrum is Script {
    RegistryContract public registryContract;
    RegistryAccess public registryAccess;
    L2Usd0 public USD0;
    L2Usd0PP public USD0PP;
    uint256 public index;

    function run() public virtual {
        if (block.chainid != 42_161) {
            console.log("This script is only for Arbitrum One");
            return;
        }
        Options memory upgradeOptions;
        //address usualArbAdmin = 0x192482bdB33B670ac7dA705cEF9E98C93abeEc9a;
        address usualArbProxyAdmin = 0xAB81Dfc22d7BE807EFd0944c9c975CbbBaEA7683;

        // Deploy Registry Access
        vm.startBroadcast();
        console.log("Sender address:", msg.sender);
        registryAccess = RegistryAccess(
            Upgrades.deployTransparentProxy(
                "RegistryAccess.sol",
                usualArbProxyAdmin,
                abi.encodeCall(RegistryAccess.initialize, (msg.sender)),
                upgradeOptions
            )
        );
        console.log("RegistryAccess address:", address(registryAccess));

        // Deploy Registry Contract
        registryContract = RegistryContract(
            Upgrades.deployTransparentProxy(
                "RegistryContract.sol",
                usualArbProxyAdmin,
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
                usualArbProxyAdmin,
                abi.encodeCall(L2Usd0.initialize, (address(registryContract), USD0Name, USD0Symbol))
            )
        );
        registryContract.setContract(CONTRACT_USD0, address(USD0));

        //Deploy USD0PP
        USD0PP = L2Usd0PP(
            Upgrades.deployTransparentProxy(
                "L2Usd0PP.sol",
                usualArbProxyAdmin,
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
        // registryAccess.grantRole(PAUSING_CONTRACTS_ROLE, HEXAGATE_PAUSER);

        // Hand over the ownership of the contracts to the multisig
        // wait 3 days to accept the transfer of admin role to the multisig
        // registryAccess.beginDefaultAdminTransfer(usualArbAdmin);
        vm.stopBroadcast();

        // logs
        console.log("Usd0 address:", address(USD0));
        console.log("Usd0PP address:", address(USD0PP));
    }

    function deriveMnemonic(uint256 offset) public returns (address account, uint256 privateKey) {
        return deriveRememberKey(vm.envString("MNEMONIC"), uint32(index + offset));
    }
}
