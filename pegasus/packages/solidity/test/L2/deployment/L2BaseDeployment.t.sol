// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
// Import script utils
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IUsd0} from "src/interfaces/token/IUsd0.sol";
import {USDC, USYC} from "src/mock/constants.sol";
import {L2Usd0} from "src/L2/token/L2Usd0.sol";
import {IUSYCAuthority, USYCRole} from "test/interfaces/IUSYCAuthority.sol";
import {IUSYC} from "test/interfaces/IUSYC.sol";
import {L2ContractScript} from "scripts/deployment/L2/L2Contracts.s.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IUSDC} from "test/interfaces/IUSDC.sol";

import {TokenMapping} from "src/TokenMapping.sol";
/// @author  Usual Tech Team
/// @title   Curve Deployment Script
/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting

contract L2BaseDeploymentTest is Test {
    L2ContractScript public deploy;
    IRegistryContract registryContract;
    IRegistryAccess registryAccess;
    L2Usd0 USD0;
    TokenMapping tokenMapping;

    address usual;
    address alice;
    address bob;

    function setUp() public virtual {
        uint256 forkId = vm.createFork("arbitrum");
        vm.selectFork(forkId);
        require(vm.activeFork() == forkId, "Fork not found");
        deploy = new L2ContractScript();
        deploy.run();
        USD0 = deploy.USD0();

        vm.label(address(USD0), "USD0");
        registryContract = deploy.registryContract();
        registryAccess = deploy.registryAccess();

        alice = deploy.alice();
        vm.label(alice, "alice");
        bob = deploy.bob();
        vm.label(bob, "bob");
    }
}
