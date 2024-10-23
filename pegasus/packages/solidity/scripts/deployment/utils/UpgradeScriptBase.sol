// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {ProxyAdmin} from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import {RegistryContract} from "src/registry/RegistryContract.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {CONTRACT_REGISTRY_ACCESS, USUAL_MULTISIG_MAINNET} from "src/constants.sol";
import {console} from "forge-std/console.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

abstract contract UpgradeScriptBase is Script {
    RegistryContract RegistryContractProxy;

    function bytesToHexString(bytes memory data) public pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory hexString = new bytes(2 + data.length * 2);

        hexString[0] = "0";
        hexString[1] = "x";
        for (uint256 i = 0; i < data.length; i++) {
            hexString[2 + 2 * i] = hexChars[uint8(data[i] >> 4)];
            hexString[3 + 2 * i] = hexChars[uint8(data[i] & 0x0f)];
        }

        return string(hexString);
    }

    function DeployImplementationAndLogs(
        string memory contractName,
        bytes32 registryKey,
        bytes memory initData
    ) public {
        Options memory emptyUpgradeOptions;
        address proxy;
        if (registryKey == bytes32(uint256(uint160(address(RegistryContractProxy))))) {
            proxy = address(RegistryContractProxy);
        } else {
            proxy = RegistryContractProxy.getContract(registryKey);
        }
        address proxyAdmin = Upgrades.getAdminAddress(proxy);
        vm.startBroadcast();
        address newImplementation = Upgrades.deployImplementation(contractName, emptyUpgradeOptions);
        vm.stopBroadcast();
        console.log(
            string(
                abi.encodePacked("Call for ", contractName, " ProxyAdmin with these parameters:")
            )
        );
        console.log("ProxyAdmin:", proxyAdmin);
        console.log("Function: upgradeAndCall (sig: 0x9623609d )");
        console.log("From(ProxyAdmin Owner):", Ownable(proxyAdmin).owner());
        console.log("Proxy:", proxy);
        console.log("Implementation:", newImplementation);
        console.log("Data: ", bytesToHexString(initData));
        console.log(
            "Selector and encoded data:",
            bytesToHexString(
                abi.encodeWithSelector(
                    ProxyAdmin.upgradeAndCall.selector, proxy, newImplementation, initData
                )
            )
        );
        console.log("");
    }

    function SetContractAndLogs(bytes32 name, address contractAddress) public view {
        console.log("Call to RegistryContract ");
        console.log("Function: setContract (sig: 0x7ed77c9c )");
        console.log("From multiSig:", USUAL_MULTISIG_MAINNET);

        console.log("To RegistryContract:", address(RegistryContractProxy));
        console.log("Name:", bytesToHexString(abi.encodePacked(name)));
        console.log("Address:", contractAddress);
        console.log(
            "Selector and encoded data:",
            bytesToHexString(
                abi.encodeWithSelector(RegistryContract.setContract.selector, name, contractAddress)
            )
        );
        console.log("");
    }

    function grantRoleAndLogs(bytes32 role, address account) public view {
        IAccessControl RegistryAccessProxy =
            IAccessControl(RegistryContractProxy.getContract(CONTRACT_REGISTRY_ACCESS));
        console.log("Call to RegistryAccess ");
        console.log("Function: grantRole (sig: 0x2f2ff15d)");
        console.log("from multiSig:", USUAL_MULTISIG_MAINNET);
        console.log("to RegistryAccess:", address(RegistryAccessProxy));
        console.log("Account:", account);
        console.log("Role:", bytesToHexString(abi.encodePacked(role)));
        console.log(
            "selector and encoded data:",
            bytesToHexString(
                abi.encodeWithSelector(IAccessControl.grantRole.selector, role, account)
            )
        );
        console.log("");
    }

    function DeployNewProxyWithImplementationAndLogsOrFail(
        string memory contractName,
        bytes32 registryKey,
        bytes memory initData
    ) public {
        require(address(RegistryContractProxy) != address(0), "RegistryContractProxy not set");

        // Check if the contract is already registered
        try RegistryContractProxy.getContract(registryKey) {
            revert("Contract already registered in RegistryContract");
        } catch {}

        // New proxy admin owner will be the same as the owner of the RegistryContractProxy
        address proxyAdminOwner =
            Ownable(Upgrades.getAdminAddress(address(RegistryContractProxy))).owner();

        // Deploy new implementation
        vm.startBroadcast();
        // Deploy new proxy
        address newProxy = Upgrades.deployTransparentProxy(contractName, proxyAdminOwner, initData);
        vm.stopBroadcast();

        console.log(
            string(
                abi.encodePacked("Deployed new proxy for ", contractName, " with these parameters:")
            )
        );
        address proxyAdmin = Upgrades.getAdminAddress(newProxy);
        address newImplementation = Upgrades.getImplementationAddress(newProxy);

        console.log("New contract:", contractName);
        console.log("Proxy:", newProxy);
        console.log("Implementation:", newImplementation);
        console.log("Proxy Admin:", proxyAdmin);
        console.log("Registry Key:", bytesToHexString(abi.encodePacked(registryKey)));
        console.log("Init Data: ", bytesToHexString(initData));
        console.log("");

        // Log the setContract call for RegistryContract
        SetContractAndLogs(registryKey, newProxy);
    }
}
