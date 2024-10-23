// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_USD0,
    CONTRACT_USD0PP,
    USD0_BURN,
    USD0_MINT,
    HEXAGATE_PAUSER,
    PAUSING_CONTRACTS_ROLE,
    DEFAULT_ADMIN_ROLE
} from "src/constants.sol";

contract VerifyScript is Script {
    IRegistryContract public registryContract;
    IRegistryAccess public registryAccess;
    address public usd0;
    address public tokenMapping;
    address public usd0PP;

    address public constant CONTRACT_REGISTRY_ARBITRUM = 0x3F44A0D493Ef5ae030fCf36a2b5d4365fb22BC4A;

    address public constant USUAL_ADMIN_ARBITRUM = 0x192482bdB33B670ac7dA705cEF9E98C93abeEc9a;

    address public constant USUAL_PROXY_ADMIN_ARBITRUM = 0xAB81Dfc22d7BE807EFd0944c9c975CbbBaEA7683;

    address usd0Arbitrum = 0x35f1C5cB7Fb977E669fD244C567Da99d8a3a6850;
    address usd0ppArbitrum = 0x2B65F9d2e4B84a2dF6ff0525741b75d1276a9C2F;
    address registryAccessArbitrum = 0x168BA269fc6CDe6115F3b03C94F55831165D374F;

    ProxyAdmin usd0ProxyAdmin;
    ProxyAdmin usd0PPProxyAdmin;
    ProxyAdmin registryAccessProxyAdmin;
    ProxyAdmin registryContractProxyAdmin;

    address public constant USD0_ADAPTER_ARBITRUM = 0xE14C486b93C3B62F76F88cf8FE4B36fb672f3B26;
    address public constant USD0PP_ADAPTER_ARBITRUM = 0xd155d91009cbE9B0204B06CE1b62bf1D793d3111;

    function run() public {
        if (block.chainid == 42_161) {
            // Mainnet
            registryContract = IRegistryContract(CONTRACT_REGISTRY_ARBITRUM);
        } else {
            revert("Unsupported network");
        }
        registryAccess = IRegistryAccess(registryContract.getContract(CONTRACT_REGISTRY_ACCESS));
        usd0 = registryContract.getContract(CONTRACT_USD0);
        usd0PP = registryContract.getContract(CONTRACT_USD0PP);

        // Set the RegistryAccess contract address and expected addresses based on the network
        if (block.chainid == 42_161) {
            console.log("Fetching addresses from Arbitrum ContractRegistry");
            // Arbitrum testnet
            verifyExpectedAddress(usd0Arbitrum, usd0);
            verifyExpectedAddress(usd0ppArbitrum, usd0PP);
            verifyExpectedAddress(registryAccessArbitrum, address(registryAccess));
            usd0ProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(usd0Arbitrum));
            usd0PPProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(usd0ppArbitrum));
            registryAccessProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(registryAccessArbitrum));
            registryContractProxyAdmin =
                ProxyAdmin(Upgrades.getAdminAddress(CONTRACT_REGISTRY_ARBITRUM));

            console.log("Verifying the owner of the admin contracts for usd0 proxy is correct");
            verifyOwner(usd0ProxyAdmin, USUAL_PROXY_ADMIN_ARBITRUM);
            console.log("USD0 ProxyAdmin OK");
            console.log("Verifying the owner of the admin contracts for usd0pp proxy is correct");
            verifyOwner(usd0PPProxyAdmin, USUAL_PROXY_ADMIN_ARBITRUM);
            console.log("USD0pp ProxyAdmin OK");
            verifyOwner(registryAccessProxyAdmin, USUAL_PROXY_ADMIN_ARBITRUM);
            console.log("RegistryAccess ProxyAdmin OK");
            verifyOwner(registryContractProxyAdmin, USUAL_PROXY_ADMIN_ARBITRUM);
            console.log("RegistryContract ProxyAdmin OK");
            console.log("Verifying Accounts Assigned the role: DEFAULT_ADMIN_ROLE");

            // LayerZero adapter ownership verification
            console.log("Verifying ownership of USD0 OFTMintAndBurnAdapter on Arbitrum");
            verifyOwnership(USD0_ADAPTER_ARBITRUM);

            console.log("Verifying ownership of USD0PP OFTMintAndBurnAdapter on Arbitrum");
            verifyOwnership(USD0PP_ADAPTER_ARBITRUM);

            console.log("Adapter ownership verification completed successfully");

            //verifyRole(DEFAULT_ADMIN_ROLE, 0x192482bdB33B670ac7dA705cEF9E98C93abeEc9a);
            //admin role will be assigned to the usual contract in 3 days
            (address pendingAdmin,) = registryAccess.pendingDefaultAdmin();
            require(pendingAdmin == USUAL_ADMIN_ARBITRUM, "Admin role not pending");
            console.log("Verifying pending Admin change for DEFAULT_ADMIN_ROLE");
            console.log("Pending Admin for DEFAULT_ADMIN_ROLE", pendingAdmin);
            //added back later
            // console.log("Verifying hexagate Assigned the role: PAUSING_CONTRACTS_ROLE");
            // verifyRole(PAUSING_CONTRACTS_ROLE, HEXAGATE_PAUSER);
        } else {
            revert("Unsupported network");
        }
    }

    function verifyRole(bytes32 role, address roleAddress) internal view {
        bool hasRole = registryAccess.hasRole(role, roleAddress);
        require(hasRole, "Role not set correctly");
        console.log("Role verified for address", roleAddress);
    }

    function verifyOwner(ProxyAdmin proxyAdmin, address owner) internal view {
        require(proxyAdmin.owner() == owner);
    }

    function verifyImplementation(address proxy, address implementation) internal view {
        require(
            Upgrades.getImplementationAddress(proxy) == implementation,
            "Implementation address for proxy is not correct"
        );
    }

    function verifyExpectedAddress(address expected, address actual) internal pure {
        require(expected == actual, "Address does not match expected on current network");
    }

    function verifyOwnership(address adapterAddress) internal view {
        Ownable adapter = Ownable(adapterAddress);
        address currentOwner = adapter.owner();

        require(
            currentOwner == USUAL_ADMIN_ARBITRUM,
            "Ownership not transferred to the expected address"
        );
        console.log("Ownership verified for adapter:", adapterAddress);
    }
}
