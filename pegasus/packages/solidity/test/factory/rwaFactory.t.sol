// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {MyERC20} from "src/mock/myERC20.sol";
import {SetupTest} from "test/setup.t.sol";
import {IRwaMock} from "src/interfaces/token/IRwaMock.sol";
import {RwaMock} from "src/mock/rwaMock.sol";

contract RwaFactoryTest is SetupTest {
    error InvalidDecimals();

    function setUp() public virtual override {
        super.setUp();
    }

    function testCreationRwa() public {
        vm.prank(admin);
        address tkn = rwaFactory.createRwa("Hashnote US Yield Coin", "USYC", 6);
        assert(tkn != address(0));
    }

    function testMultipleCreationRwa() public {
        vm.prank(admin);
        rwaFactory.createRwa("Hashnote US Yield Coin", "USYC", 6);
        vm.prank(admin);
        rwaFactory.createRwa("FRA fdn Fiat Token EUR", "ffTFRE", 6);
    }

    function testCreationRwaFailName() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidName.selector));
        rwaFactory.createRwa("", "", 6);
    }

    function testCreationRwaFailSymbol() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidSymbol.selector));
        rwaFactory.createRwa("USYC", "", 6);
    }

    function testCreationRwaFailDecimals() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidDecimals.selector));
        rwaFactory.createRwa("USYC", "USYC", 0);
    }

    function testMintRwa() public {
        testCreationRwa();
        address token = rwaFactory.getRwaFromSymbol("USYC");
        // alice needs to be whitelisted
        _whitelistRWA(token, alice);
        IRwaMock(token).mint(alice, 100);
        assertEq(IRwaMock(token).balanceOf(alice), 100);
    }

    function testMintRwaFuzzing(uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max - 1);
        testCreationRwa();
        address token = rwaFactory.getRwaFromSymbol("USYC");
        // alice needs to be whitelisted
        _whitelistRWA(token, alice);
        IRwaMock(token).mint(alice, amount);
        assertEq(IRwaMock(token).balanceOf(alice), amount);
    }

    function testMintRwaEuro() public {
        vm.prank(admin);
        rwaFactory.createRwa("FRA fdn Fiat Token EUR", "ffTFRE", 6);
        address token = rwaFactory.getRwaFromSymbol("ffTFRE");
        // alice needs to be whitelisted
        _whitelistRWA(token, alice);
        IRwaMock(token).mint(alice, 100);
        assertEq(IRwaMock(token).balanceOf(alice), 100);
    }

    function testGetRwaZero() public {
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        rwaFactory.getRwaFromSymbol("USYC");
    }

    function testGetRwa() public {
        testCreationRwa();
        address token = rwaFactory.getRwaFromSymbol("USYC");
        assertEq(token, rwaFactory.getRwaFromSymbol("USYC"));
    }

    function testGetRwaFail() public {
        testCreationRwa();
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        rwaFactory.getRwaFromSymbol("ffTFRE");
    }

    function testisRwa() public {
        testCreationRwa();
        address token = rwaFactory.getRwaFromSymbol("USYC");
        assertEq(rwaFactory.isRwa(token), true);
    }

    function testisRwaZero() public {
        testCreationRwa();
        assertEq(rwaFactory.isRwa(address(0)), false);
    }

    function testisRwaNotRwa() public {
        testCreationRwa();
        assertEq(rwaFactory.isRwa(address(registryContract)), false);
    }

    function testRemoveRwa() public {
        testCreationRwa();
        address token = rwaFactory.getRwaFromSymbol("USYC");
        assertEq(rwaFactory.isRwa(token), true);
        vm.prank(admin);
        rwaFactory.removeRwa(token);
        assertEq(rwaFactory.isRwa(token), false);
    }

    function testAddRwa() public {
        vm.prank(admin);
        address rwa = address(rwaFactory.createRwa("A", "AAA", 6));
        assertTrue(rwaFactory.isRwa(rwa));
        assertEq(rwaFactory.getRwasLength(), 1);
    }

    function testCreateMultipleRwa() public {
        vm.prank(admin);
        address rwa1 = address(rwaFactory.createRwa("A", "AAA", 6));
        vm.prank(admin);
        address rwa2 = address(rwaFactory.createRwa("B", "BBB", 6));
        vm.prank(admin);
        address rwa3 = address(rwaFactory.createRwa("C", "CCC", 6));
        vm.prank(admin);
        address rwa4 = address(rwaFactory.createRwa("D", "DDD", 6));

        assertTrue(rwaFactory.isRwa(rwa1));
        assertTrue(rwaFactory.isRwa(rwa2));
        assertTrue(rwaFactory.isRwa(rwa3));
        assertTrue(rwaFactory.isRwa(rwa4));
        assertEq(rwaFactory.getRwasLength(), 4);
    }

    function removeRwaMultiple() public {
        vm.prank(admin);
        address rwa1 = address(rwaFactory.createRwa("A", "AAA", 6));
        vm.prank(admin);
        address rwa2 = address(rwaFactory.createRwa("B", "BBB", 6));
        vm.prank(admin);
        address rwa3 = address(rwaFactory.createRwa("C", "CCC", 6));
        vm.prank(admin);
        address rwa4 = address(rwaFactory.createRwa("D", "DDD", 6));

        assertTrue(rwaFactory.isRwa(rwa1));
        assertTrue(rwaFactory.isRwa(rwa2));
        assertTrue(rwaFactory.isRwa(rwa3));
        assertTrue(rwaFactory.isRwa(rwa4));
        assertEq(rwaFactory.getRwasLength(), 3);
        vm.prank(admin);
        rwaFactory.removeRwa(rwa3);
        assertEq(rwaFactory.getRwasLength(), 2);
    }

    function testRemoveRwaInvalidToken() public {
        vm.prank(admin);
        address(rwaFactory.createRwa("A", "AAA", 6));
        vm.prank(admin);
        address USDT = address(new MyERC20("USDT", "USDT", 6));
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        rwaFactory.removeRwa(address(USDT));
    }

    function testHasRwaToken() public {
        vm.prank(admin);
        address(rwaFactory.createRwa("A", "AAA", 6));
        vm.prank(admin);
        address rwa1 = address(rwaFactory.createRwa("B", "BBBB", 6));
        // alice needs to be whitelisted
        _whitelistRWA(rwa1, alice);

        RwaMock(rwa1).mint(alice, 100);
        assertTrue(rwaFactory.hasRwaToken(alice));
    }

    function testHasRwaTokenFail() public {
        vm.prank(admin);
        address(rwaFactory.createRwa("A", "AAA", 6));
        vm.prank(admin);
        address(rwaFactory.createRwa("B", "BBBB", 6));
        assertFalse(rwaFactory.hasRwaToken(alice));
    }

    function testGetRwasLength() public {
        vm.prank(admin);
        rwaFactory.createRwa("A", "AAA", 6);
        assertEq(rwaFactory.getRwasLength(), 1);
    }
}
