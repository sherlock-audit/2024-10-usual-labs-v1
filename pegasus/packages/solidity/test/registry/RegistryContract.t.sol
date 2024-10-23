// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {MyERC20} from "src/mock/myERC20.sol";
import {SetupTest} from "test/setup.t.sol";
import {RegistryContract} from "src/registry/RegistryContract.sol";
import {CONTRACT_DAO_COLLATERAL} from "src/constants.sol";
import {CONTRACT_RWA_FACTORY, REGISTRY_SALT} from "src/mock/constants.sol";

contract RegistryContractTest is SetupTest {
    // address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    string[] private _currencies;
    address myRwa;

    function setUp() public virtual override {
        super.setUp();
        myRwa = address(new MyERC20("MyRwa", "RWA", 6));
    }

    function testInitialize() public {
        registryContract = new RegistryContract{salt: REGISTRY_SALT}();
        _resetInitializerImplementation(address(registryContract));
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        registryContract.initialize(address(0));
    }

    function testSetDaoCollateral() external {
        vm.prank(admin);
        registryContract.setContract(CONTRACT_DAO_COLLATERAL, address(daoCollateral));
        assertEq(registryContract.getContract(CONTRACT_DAO_COLLATERAL), address(daoCollateral));
    }

    function testSetDaoCollateralFailIfNotAdmin() external {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        registryContract.setContract(CONTRACT_DAO_COLLATERAL, address(daoCollateral));
    }

    function testSetDaoCollateralZero() external {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        registryContract.setContract(CONTRACT_DAO_COLLATERAL, address(0));
    }

    function testSetDaoCollateralNullName() external {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(InvalidName.selector));
        registryContract.setContract(bytes32(0), address(daoCollateral));
    }

    function testGetDaoCollateralNotSet() external {
        RegistryContract tmpRegistryContract = new RegistryContract();
        _resetInitializerImplementation(address(tmpRegistryContract));
        tmpRegistryContract.initialize(address(registryAccess));

        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        tmpRegistryContract.getContract(CONTRACT_DAO_COLLATERAL);
    }

    function testSetRwaFactory() external {
        vm.prank(admin);
        registryContract.setContract(CONTRACT_RWA_FACTORY, address(1));
        assertEq(registryContract.getContract(CONTRACT_RWA_FACTORY), address(1));
    }

    function testSetTwiceShouldWork() external {
        vm.prank(admin);
        registryContract.setContract(CONTRACT_RWA_FACTORY, address(1));
        assertEq(registryContract.getContract(CONTRACT_RWA_FACTORY), address(1));
        vm.prank(admin);
        registryContract.setContract(CONTRACT_RWA_FACTORY, address(2));
        assertEq(registryContract.getContract(CONTRACT_RWA_FACTORY), address(2));
    }

    function testSetRwaFactoryFail() external {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        registryContract.setContract(CONTRACT_RWA_FACTORY, address(1));
    }

    function testSetRwaFactoryZero() external {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        registryContract.setContract(CONTRACT_RWA_FACTORY, address(0));
    }

    function testGetRwaFactoryNotSet() external {
        RegistryContract tmpRegistryContract = new RegistryContract();
        _resetInitializerImplementation(address(tmpRegistryContract));
        tmpRegistryContract.initialize(address(registryAccess));

        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        tmpRegistryContract.getContract(CONTRACT_RWA_FACTORY);
    }

    function testRegistryInitializeRevertIfZeroAddress() external {
        _resetInitializerImplementation(address(registryContract));
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        registryContract.initialize(address(0));
    }
}
