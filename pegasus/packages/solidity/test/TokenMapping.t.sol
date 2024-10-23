// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Usd0Harness} from "src/mock/token/Usd0Harness.sol";
import {SetupTest} from "./setup.t.sol";
import {MyERC20} from "src/mock/myERC20.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IUsd0} from "src/interfaces/token/IUsd0.sol";
import {SameValue} from "src/errors.sol";
import {CONTRACT_USD0} from "src/constants.sol";
import {USD0Name, USD0Symbol} from "src/mock/constants.sol";
import {TooManyRWA, NullAddress} from "src/errors.sol";
import {TokenMapping} from "src/TokenMapping.sol";

contract ZeroDecimalERC20 is ERC20 {
    constructor() ERC20("ZeroDecimalERC20", "ZERO") {}

    function decimals() public view virtual override returns (uint8) {
        return 0;
    }
}

contract TokenMappingTest is SetupTest {
    address myRwa;

    IUsd0 stbc;

    event Initialized(uint64);

    function setUp() public virtual override {
        super.setUp();

        myRwa = rwaFactory.createRwa("rwa", "rwa", 6);
        stbc = new Usd0Harness();
        _resetInitializerImplementation(address(stbc));
        Usd0Harness(address(stbc)).initialize(address(registryContract), USD0Name, USD0Symbol);
        _resetInitializerImplementation(address(stbc));
        Usd0Harness(address(stbc)).initializeV1(registryContract);
    }

    function testConstructor() external {
        vm.expectEmit();
        emit Initialized(type(uint64).max);

        TokenMapping tokenMapping = new TokenMapping();
        assertTrue(address(tokenMapping) != address(0));
    }

    function testInitialize() public {
        tokenMapping = new TokenMapping();
        _resetInitializerImplementation(address(tokenMapping));
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        tokenMapping.initialize(address(0), address(registryContract));
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        tokenMapping.initialize(address(registryAccess), address(0));
    }

    function testSetUsd0ToRwa() public {
        vm.prank(admin);
        registryContract.setContract(CONTRACT_USD0, address(stbc));

        address rwa = rwaFactory.createRwa("rwa", "rwa", 6);
        // allow rwa
        vm.prank(admin);
        tokenMapping.addUsd0Rwa(rwa);

        uint256 lastId = tokenMapping.getLastUsd0RwaId();
        assertEq(lastId, 1);
        assertTrue(tokenMapping.isUsd0Collateral(rwa));
        assertTrue(tokenMapping.getUsd0RwaById(lastId) == rwa);
    }

    function testSetUsd0ToSeveralRwas() public {
        vm.prank(admin);
        registryContract.setContract(CONTRACT_USD0, address(stbc));

        address rwa1 = rwaFactory.createRwa("rwa1", "rwa1", 6);
        address rwa2 = rwaFactory.createRwa("rwa2", "rwa2", 6);
        vm.startPrank(admin);
        tokenMapping.addUsd0Rwa(rwa1);
        tokenMapping.addUsd0Rwa(rwa2);
        vm.stopPrank();

        uint256 lastId = tokenMapping.getLastUsd0RwaId();
        assertTrue(tokenMapping.getUsd0RwaById(lastId) == rwa2);
        vm.expectRevert(abi.encodeWithSelector(InvalidToken.selector));
        tokenMapping.getUsd0RwaById(0);
        assertTrue(tokenMapping.getUsd0RwaById(1) == rwa1);
    }

    function testSetMoreThanTenRwaFail() public {
        vm.prank(address(admin));
        registryContract.setContract(CONTRACT_USD0, address(stbc));

        address rwa1 = rwaFactory.createRwa("rwa1", "rwa1", 6);
        address rwa2 = rwaFactory.createRwa("rwa2", "rwa2", 6);
        address rwa3 = rwaFactory.createRwa("rwa3", "rwa3", 6);
        address rwa4 = rwaFactory.createRwa("rwa4", "rwa4", 6);
        address rwa5 = rwaFactory.createRwa("rwa5", "rwa5", 6);
        address rwa6 = rwaFactory.createRwa("rwa6", "rwa6", 6);
        address rwa7 = rwaFactory.createRwa("rwa7", "rwa7", 6);
        address rwa8 = rwaFactory.createRwa("rwa8", "rwa8", 6);
        address rwa9 = rwaFactory.createRwa("rwa9", "rwa9", 6);
        address rwa10 = rwaFactory.createRwa("rwa10", "rwa10", 6);
        address rwa11 = rwaFactory.createRwa("rwa11", "rwa11", 6);
        vm.startPrank(admin);
        tokenMapping.addUsd0Rwa(rwa1);
        tokenMapping.addUsd0Rwa(rwa2);
        tokenMapping.addUsd0Rwa(rwa3);
        tokenMapping.addUsd0Rwa(rwa4);
        tokenMapping.addUsd0Rwa(rwa5);
        tokenMapping.addUsd0Rwa(rwa6);
        tokenMapping.addUsd0Rwa(rwa7);
        tokenMapping.addUsd0Rwa(rwa8);
        tokenMapping.addUsd0Rwa(rwa9);
        tokenMapping.addUsd0Rwa(rwa10);
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(TooManyRWA.selector));
        tokenMapping.addUsd0Rwa(rwa11);
    }

    function testSetRwaToUsd0() public {
        address rwa = rwaFactory.createRwa("rwa", "rwa", 6);
        vm.prank(admin);
        tokenMapping.addUsd0Rwa(rwa);
        assertTrue(tokenMapping.isUsd0Collateral(rwa));
    }

    function testSetRwaToUsd0FailZero() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        tokenMapping.addUsd0Rwa(address(0));
    }

    function testSetRwaToUsd0FailIfSameValue() public {
        address rwa = rwaFactory.createRwa("rwa", "rwa", 6);
        vm.prank(admin);
        tokenMapping.addUsd0Rwa(rwa);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        tokenMapping.addUsd0Rwa(rwa);
    }

    function testGetAllUsd0Rwa() public {
        vm.prank(admin);
        registryContract.setContract(CONTRACT_USD0, address(stbc));

        address rwa1 = rwaFactory.createRwa("rwa1", "rwa1", 6);
        address rwa2 = rwaFactory.createRwa("rwa2", "rwa2", 6);
        vm.startPrank(admin);
        tokenMapping.addUsd0Rwa(rwa1);
        tokenMapping.addUsd0Rwa(rwa2);
        vm.stopPrank();

        address[] memory rwas = tokenMapping.getAllUsd0Rwa();
        assertTrue(rwas.length == 2);
        assertTrue(rwas[0] == rwa1);
        assertTrue(rwas[1] == rwa2);
    }

    function testSetRwa() external {
        vm.prank(admin);
        tokenMapping.addUsd0Rwa(myRwa);
        assertTrue(tokenMapping.isUsd0Collateral(myRwa));
    }

    function testSetRwaShouldFailIfNoDecimals() external {
        ZeroDecimalERC20 zeroDecimalERC20 = new ZeroDecimalERC20();
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Invalid.selector));
        tokenMapping.addUsd0Rwa(address(zeroDecimalERC20));
    }

    function testSetRwaRevertIfNotAuthorized() external {
        vm.prank(address(bob));
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        tokenMapping.addUsd0Rwa(myRwa);
    }

    function testSetRwaRevertIfSameValue() external {
        vm.prank(admin);
        tokenMapping.addUsd0Rwa(myRwa);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        tokenMapping.addUsd0Rwa(myRwa);
    }

    function testInitializeRevertIfNullAddressForRegistryAccess() external {
        _resetInitializerImplementation(address(tokenMapping));
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        tokenMapping.initialize(address(0), address(registryContract));
    }

    function testInitializeRevertIfNullAddressForRegistryContract() external {
        _resetInitializerImplementation(address(tokenMapping));
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        tokenMapping.initialize(address(registryAccess), address(0));
    }
}
