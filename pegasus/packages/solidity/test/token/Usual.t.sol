// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SetupTest} from "test/setup.t.sol";
import {USUAL_MINT, USUALName, USUALSymbol} from "src/constants.sol";
import {NotAuthorized, Blacklisted, SameValue} from "src/errors.sol";

import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC165Checker} from "openzeppelin-contracts/utils/introspection/ERC165Checker.sol";
import {Pausable} from "openzeppelin-contracts/utils/Pausable.sol";

// @title: USUAL test contract
// @notice: Contract to test USUAL token implementation

contract UsualTest is SetupTest {
    event Blacklist(address account);
    event UnBlacklist(address account);

    function setUp() public override {
        super.setUp();
    }

    function testName() external view {
        assertEq(USUALName, usualToken.name());
    }

    function testSymbol() external view {
        assertEq(USUALSymbol, usualToken.symbol());
    }

    function testUsualErc20Compliance() external view {
        ERC165Checker.supportsInterface(address(usualToken), type(IERC20).interfaceId);
    }

    function mintTokensToAlice() public {
        vm.prank(admin);
        usualToken.mint(alice, 2e18);
        assertEq(usualToken.totalSupply(), usualToken.balanceOf(alice));
    }

    function testCreationOfUsualToken() public {
        _resetInitializerImplementation(address(usualToken));
        usualToken.initialize(address(registryContract), "USUAL", "USUAL");
    }

    function testInitializeShouldFailWithNullAddress() public {
        _resetInitializerImplementation(address(usualToken));
        vm.expectRevert(abi.encodeWithSelector(NullContract.selector));
        usualToken.initialize(address(0), "USUAL", "USUAL");
    }

    // Additional test functions for the UsualTest contract

    function testUnauthorizedAccessToMintAndBurn() public {
        // Attempt to mint by a non-authorized address
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualToken.mint(alice, 1e18);

        // Attempt to burn by a non-authorized address
        vm.prank(admin);
        usualToken.mint(alice, 10e18); // Mint some tokens for Alice
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualToken.burnFrom(alice, 5e18);
    }

    function testRoleChangesAffectingMintAndBurn() public {
        // Grant and revoke roles dynamically and test access control
        vm.startPrank(admin);

        registryAccess.grantRole(USUAL_MINT, carol);
        vm.stopPrank();
        vm.prank(carol);
        usualToken.mint(alice, 1e18); // Should succeed now that Carol can mint

        vm.prank(admin);
        registryAccess.revokeRole(USUAL_MINT, carol);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualToken.mint(alice, 1e18); // Should fail now that Carol's mint role is revoked
    }

    function testMintNullAddress() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        usualToken.mint(address(0), 2e18);
    }

    function testMintAmountZero() public {
        vm.prank(admin);
        vm.expectRevert(AmountIsZero.selector);
        usualToken.mint(alice, 0);
    }

    function testBurnFrom() public {
        vm.startPrank(admin);
        usualToken.mint(alice, 10e18);
        assertEq(usualToken.balanceOf(alice), 10e18);

        usualToken.burnFrom(alice, 8e18);

        assertEq(usualToken.totalSupply(), 2e18);
        assertEq(usualToken.balanceOf(alice), 2e18);
    }

    function testBurnFromFail() public {
        vm.prank(admin);
        usualToken.mint(alice, 10e18);
        assertEq(usualToken.balanceOf(alice), 10e18);

        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualToken.burnFrom(alice, 8e18);

        assertEq(usualToken.totalSupply(), 10e18);
        assertEq(usualToken.balanceOf(alice), 10e18);
    }

    function testBurn() public {
        vm.startPrank(admin);
        usualToken.mint(admin, 10e18);

        usualToken.burn(8e18);

        assertEq(usualToken.balanceOf(admin), 2e18);
    }

    function testBurnFail() public {
        vm.prank(admin);
        usualToken.mint(alice, 10e18);
        assertEq(usualToken.balanceOf(alice), 10e18);

        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualToken.burn(8e18);

        assertEq(usualToken.totalSupply(), 10e18);
        assertEq(usualToken.balanceOf(alice), 10e18);
    }

    function testApprove() public {
        assertTrue(usualToken.approve(alice, 1e18));
        assertEq(usualToken.allowance(address(this), alice), 1e18);
    }

    function testApproveZeroAmount() public {
        assertTrue(usualToken.approve(alice, 0));
        assertEq(usualToken.allowance(address(this), alice), 0);
    }

    function testTransfer() external {
        mintTokensToAlice();
        vm.startPrank(alice);
        usualToken.transfer(bob, 0.5e18);
        assertEq(usualToken.balanceOf(bob), 0.5e18);
        assertEq(usualToken.balanceOf(alice), 1.5e18);
        vm.stopPrank();
    }

    function testTransferZeroAmount() external {
        mintTokensToAlice();
        vm.startPrank(alice);
        usualToken.transfer(bob, 0);
        assertEq(usualToken.balanceOf(bob), 0);
        assertEq(usualToken.balanceOf(alice), 2e18);
        vm.stopPrank();
    }

    function testTransferFrom() external {
        mintTokensToAlice();
        vm.prank(alice);
        usualToken.approve(address(this), 1e18);
        assertTrue(usualToken.transferFrom(alice, bob, 0.7e18));
        assertEq(usualToken.allowance(alice, address(this)), 1e18 - 0.7e18);
        assertEq(usualToken.balanceOf(alice), 2e18 - 0.7e18);
        assertEq(usualToken.balanceOf(bob), 0.7e18);
    }

    function testTransferFromWithPermit(uint256 amount) public {
        amount = bound(amount, 100_000_000_000, type(uint128).max);

        vm.prank(admin);
        usualToken.mint(alice, amount);

        vm.startPrank(alice);
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) =
            _getSelfPermitData(address(usualToken), alice, alicePrivKey, bob, amount, deadline);

        IERC20Permit(address(usualToken)).permit(alice, bob, amount, deadline, v, r, s);

        vm.stopPrank();
        vm.prank(bob);
        usualToken.transferFrom(alice, bob, amount);

        assertEq(usualToken.balanceOf(bob), amount);
        assertEq(usualToken.balanceOf(alice), 0);
    }

    function testPauseUnPause() external {
        mintTokensToAlice();

        vm.prank(pauser);
        usualToken.pause();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        usualToken.transfer(bob, 1e18);
        vm.prank(admin);
        usualToken.unpause();
        vm.prank(alice);
        usualToken.transfer(bob, 1e18);
    }

    function testPauseUnPauseShouldFailWhenNotAuthorized() external {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualToken.pause();
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualToken.unpause();
    }

    function testBlacklistUser() external {
        mintTokensToAlice();
        vm.startPrank(blacklistOperator);

        usualToken.blacklist(alice);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        usualToken.blacklist(alice);
        vm.stopPrank();

        vm.assertTrue(usualToken.isBlacklisted(alice));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Blacklisted.selector));
        usualToken.transfer(bob, 1e18);

        vm.startPrank(blacklistOperator);
        usualToken.unBlacklist(alice);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        usualToken.unBlacklist(alice);
        vm.stopPrank();

        vm.prank(alice);
        usualToken.transfer(bob, 1e18);
    }

    function testBlacklistShouldRevertIfAddressIsZero() external {
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        usualToken.blacklist(address(0));
    }

    function testBlacklistAndUnBlacklistEmitsEvents() external {
        mintTokensToAlice();
        vm.startPrank(blacklistOperator);
        vm.expectEmit();
        emit Blacklist(alice);
        usualToken.blacklist(alice);

        vm.expectEmit();
        emit UnBlacklist(alice);
        usualToken.unBlacklist(alice);
    }

    function testOnlyAdminCanUseBlacklist(address user) external {
        vm.assume(user != blacklistOperator);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualToken.blacklist(alice);

        vm.prank(blacklistOperator);
        usualToken.blacklist(alice);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualToken.unBlacklist(alice);
    }
}
