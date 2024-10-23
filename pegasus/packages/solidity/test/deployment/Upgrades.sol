// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
// Import script utils
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FinalConfigScript} from "scripts/deployment/FinalConfig.s.sol";

import {RegistryAccess} from "src/registry/RegistryAccess.sol";
import {RegistryContract} from "src/registry/RegistryContract.sol";
import {TokenMapping} from "src/TokenMapping.sol";

import {Usd0} from "src/token/Usd0.sol";
import {Usd0PP} from "src/token/Usd0PP.sol";

import {DaoCollateral} from "src/daoCollateral/DaoCollateral.sol";

import {SwapperEngine} from "src/swapperEngine/SwapperEngine.sol";

import {ClassicalOracle} from "src/oracles/ClassicalOracle.sol";
import {UsualOracle} from "src/oracles/UsualOracle.sol";

contract V2 {
    function initializeV2Test() public {}

    function version() public pure returns (uint256) {
        return 2;
    }
}

/*
- Usd0
- RegistryAccess
- RegistryContract
- TokenMapping
- Usd0PP
- DaoCollateral
- ClassicalOracle
- UsualOracle
*/

/// @custom:oz-upgrades-from Usd0
contract Usd02 is Usd0, V2 {}

/// @custom:oz-upgrades-from RegistryAccess
contract RegistryAccess2 is RegistryAccess, V2 {}

/// @custom:oz-upgrades-from RegistryContract
contract RegistryContract2 is RegistryContract, V2 {}

/// @custom:oz-upgrades-from TokenMapping
contract TokenMapping2 is TokenMapping, V2 {}

/// @custom:oz-upgrades-from Usd0PP
contract Usd0PP2 is Usd0PP, V2 {}

/// @custom:oz-upgrades-from DaoCollateral
contract DaoCollateral2 is DaoCollateral, V2 {}

/// @custom:oz-upgrades-from SwapperEngine
contract SwapperEngine2 is SwapperEngine, V2 {}

/// @custom:oz-upgrades-from ClassicalOracle
contract ClassicalOracle2 is ClassicalOracle, V2 {}

/// @custom:oz-upgrades-from UsualOracle
contract UsualOracle2 is UsualOracle, V2 {}

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract DeploymentTest is Test {
    FinalConfigScript public deploy;

    function setUp() public {
        uint256 forkId = vm.createFork("eth");
        vm.selectFork(forkId);
        require(vm.activeFork() == forkId, "Fork not found");
        deploy = new FinalConfigScript();
        deploy.run();
    }

    function testUpgradeContracts() public {
        /*
        - Usd0
        - RegistryAccess
        - RegistryContract
        - TokenMapping
        - Usd0PP
        - DaoCollateral
        - SwapperEngine
        - ClassicalOracle
        - UsualOracle
        */
        Upgrades.upgradeProxy(
            address(deploy.USD0()),
            "Upgrades.sol:Usd02",
            abi.encodeWithSelector(V2.initializeV2Test.selector),
            deploy.usualProxyAdmin()
        );
        Usd02 stbc = Usd02(address(deploy.USD0()));
        assertEq(stbc.version(), 2);

        Upgrades.upgradeProxy(
            address(deploy.registryAccess()),
            "Upgrades.sol:RegistryAccess2",
            abi.encodeWithSelector(V2.initializeV2Test.selector),
            deploy.usualProxyAdmin()
        );
        RegistryAccess2 registryAccess = RegistryAccess2(address(deploy.registryAccess()));
        assertEq(registryAccess.version(), 2);

        Upgrades.upgradeProxy(
            address(deploy.registryContract()),
            "Upgrades.sol:RegistryContract2",
            abi.encodeWithSelector(V2.initializeV2Test.selector),
            deploy.usualProxyAdmin()
        );
        RegistryContract2 registryContract = RegistryContract2(address(deploy.registryContract()));
        assertEq(registryContract.version(), 2);

        Upgrades.upgradeProxy(
            address(deploy.tokenMapping()),
            "Upgrades.sol:TokenMapping2",
            abi.encodeWithSelector(V2.initializeV2Test.selector),
            deploy.usualProxyAdmin()
        );
        TokenMapping2 tokenMapping = TokenMapping2(address(deploy.tokenMapping()));
        assertEq(tokenMapping.version(), 2);

        Upgrades.upgradeProxy(
            address(deploy.usd0PP()),
            "Upgrades.sol:Usd0PP2",
            abi.encodeWithSelector(V2.initializeV2Test.selector),
            deploy.usualProxyAdmin()
        );
        Usd0PP2 usd0PP = Usd0PP2(address(deploy.usd0PP()));
        assertEq(usd0PP.version(), 2);

        Upgrades.upgradeProxy(
            address(deploy.daoCollateral()),
            "Upgrades.sol:DaoCollateral2",
            abi.encodeWithSelector(V2.initializeV2Test.selector),
            deploy.usualProxyAdmin()
        );
        DaoCollateral2 daoCollateral = DaoCollateral2(address(deploy.daoCollateral()));
        assertEq(daoCollateral.version(), 2);

        Upgrades.upgradeProxy(
            address(deploy.swapperEngine()),
            "Upgrades.sol:SwapperEngine2",
            abi.encodeWithSelector(V2.initializeV2Test.selector),
            deploy.usualProxyAdmin()
        );
        SwapperEngine2 swapperEngine = SwapperEngine2(address(deploy.swapperEngine()));
        assertEq(swapperEngine.version(), 2);

        Upgrades.upgradeProxy(
            address(deploy.classicalOracle()),
            "Upgrades.sol:ClassicalOracle2",
            abi.encodeWithSelector(V2.initializeV2Test.selector),
            deploy.usualProxyAdmin()
        );
        ClassicalOracle2 classicalOracle = ClassicalOracle2(address(deploy.classicalOracle()));
        assertEq(classicalOracle.version(), 2);

        Upgrades.upgradeProxy(
            address(deploy.usualOracle()),
            "Upgrades.sol:UsualOracle2",
            abi.encodeWithSelector(V2.initializeV2Test.selector),
            deploy.usualProxyAdmin()
        );
        UsualOracle2 usualOracle = UsualOracle2(address(deploy.usualOracle()));
        assertEq(usualOracle.version(), 2);
    }

    function _resetInitializerImplementation(address implementation) internal {
        // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
        bytes32 INITIALIZABLE_STORAGE =
            0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
        // Set the storage slot to uninitialized
        vm.store(address(implementation), INITIALIZABLE_STORAGE, 0);
    }
}
