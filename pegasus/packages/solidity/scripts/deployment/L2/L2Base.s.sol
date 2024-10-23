// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";

import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";

import {L2Usd0} from "src/L2/token/L2Usd0.sol";
import {L2Usd0PP} from "src/L2/token/L2Usd0PP.sol";
import {CONTRACT_REGISTRY_ACCESS, CONTRACT_USD0} from "src/constants.sol";

import {console} from "forge-std/console.sol";

contract L2BaseScript is Script {
    IRegistryContract public registryContract;
    IRegistryAccess public registryAccess;
    L2Usd0 public USD0;
    L2Usd0PP public USD0PP;

    address public alice;
    uint256 public alicePrivateKey;
    address public bob;
    uint256 public bobPrivateKey;
    address public deployer;
    uint256 public deployerPrivateKey;
    address public usual;
    uint256 public usualPrivateKey;
    address public hashnote;
    uint256 public hashnotePrivateKey;
    address public treasury;
    uint256 public treasuryPrivateKey;
    address public usdInsurance;
    uint256 public usdInsurancePrivateKey;
    address public usualProxyAdmin;
    uint256 public usualProxyAdminPrivateKey;

    uint256 public index;

    function run() public virtual {
        index = vm.envOr("MNEMONIC_INDEX", uint256(0));
        (alice, alicePrivateKey) = deriveMnemonic(0);
        (bob, bobPrivateKey) = deriveMnemonic(1);
        (deployer, deployerPrivateKey) = deriveMnemonic(2);
        (usual, usualPrivateKey) = deriveMnemonic(3);
        (treasury, treasuryPrivateKey) = deriveMnemonic(4);
        (usdInsurance, usdInsurancePrivateKey) = deriveMnemonic(5);
        (hashnote, hashnotePrivateKey) = deriveMnemonic(6);
        (usualProxyAdmin, usualProxyAdminPrivateKey) = deriveMnemonic(7);

        try vm.envAddress("L2_REGISTRY_CONTRACT") returns (address registryContract_) {
            registryContract = IRegistryContract(registryContract_);
        } catch {}

        if (address(registryContract) != address(0) && address(registryContract).code.length != 0) {
            registryAccess = IRegistryAccess(registryContract.getContract(CONTRACT_REGISTRY_ACCESS));
            USD0 = L2Usd0(registryContract.getContract(CONTRACT_USD0));

            vm.label(address(registryAccess), "L2RegistryAccess");
            vm.label(address(USD0), "L2USD0");
        }
        console.log("RegistryContract address:", address(registryContract));
        console.log("RegistryAccess address:", address(registryAccess));
        console.log("UsualProxyAdmin address:", address(usualProxyAdmin));
        console.log("Usual address:", address(usual));
    }

    function deriveMnemonic(uint256 offset) public returns (address account, uint256 privateKey) {
        return deriveRememberKey(vm.envString("MNEMONIC"), uint32(index + offset));
    }
}
