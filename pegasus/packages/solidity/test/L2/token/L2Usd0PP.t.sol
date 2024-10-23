// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {L2SetupTest} from "test/L2/L2Setup.t.sol";
import {L2Usd0PP} from "src/L2/token/L2Usd0PP.sol";

import {
    CONTRACT_USD0PP,
    CONTRACT_TREASURY,
    USD0PP_MINT,
    USD0PP_BURN,
    PAUSING_CONTRACTS_ROLE
} from "src/constants.sol";
import {USDPPName, USDPPSymbol} from "src/mock/constants.sol";
import {InvalidName, InvalidSymbol, AmountIsZero, Blacklisted, SameValue} from "src/errors.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import {L2Usd0} from "src/L2/token/L2Usd0.sol";
import {Pausable} from "openzeppelin-contracts/utils/Pausable.sol";

contract L2Usd0PPTest is L2SetupTest {
    event Blacklist(address account);
    event UnBlacklist(address account);
    event Initialized(uint64 version);

    L2Usd0 public usd0Token;

    function setUp() public virtual override {
        uint256 forkId = vm.createFork("arbitrum");
        vm.selectFork(forkId);
        super.setUp();
        usd0Token = stbcToken;
        // give mint role to usual
        _adminGiveUsd0ppMintRoleTo(usual);
        // give pause role to admin
        _adminGivePauseRoleTo(pauser);
    }

    function testCreateUSD0pp() public {
        usd0PP = new L2Usd0PP();
        _resetInitializerImplementation(address(usd0PP));
        usd0PP.initialize(address(registryContract), USDPPName, USDPPSymbol);
    }

    function testTransferAndCallShouldWork() public {
        _allowlistAliceAndMintTokens();

        assertEq(usd0PP.balanceOf(bob), 0);
        vm.prank(alice);
        usd0PP.transferAndCall(bob, 1e18, "0x");
        assertEq(usd0PP.balanceOf(bob), 1e18);
        assertEq(usd0PP.balanceOf(alice), 1e18);
        // should revert when transferring to non IERC677Receiver contract
        vm.expectRevert();
        vm.prank(alice);
        usd0PP.transferAndCall(address(usd0Token), 1e18, "0x");
    }

    function testConstructor() public {
        vm.expectEmit();
        emit Initialized(type(uint64).max);
        L2Usd0PP l2usd0pp = new L2Usd0PP();
        assertTrue(address(l2usd0pp) != address(0));
    }

    function testCreateUsd0PPFailIfIncorrect() public {
        vm.warp(10);

        L2Usd0PP lsausUSbadName = new L2Usd0PP();
        _resetInitializerImplementation(address(lsausUSbadName));
        vm.expectRevert(abi.encodeWithSelector(InvalidName.selector));
        vm.prank(admin);
        lsausUSbadName.initialize(address(registryContract), "", "USD0PP");

        L2Usd0PP lsausUSbadSymbol = new L2Usd0PP();
        _resetInitializerImplementation(address(lsausUSbadSymbol));
        vm.expectRevert(abi.encodeWithSelector(InvalidSymbol.selector));
        vm.prank(admin);
        lsausUSbadSymbol.initialize(address(registryContract), "USD0PP", "");
    }

    function _adminGiveUsd0ppMintRoleTo(address user) internal {
        vm.prank(admin);
        registryAccess.grantRole(USD0PP_MINT, user);
    }

    function _adminGivePauseRoleTo(address user) internal {
        vm.prank(admin);
        registryAccess.grantRole(PAUSING_CONTRACTS_ROLE, user);
    }

    function _adminGiveUsd0ppBurnRoleTo(address user) internal {
        vm.prank(admin);
        registryAccess.grantRole(USD0PP_BURN, user);
    }

    function testName() external view {
        assertEq(USDPPName, usd0PP.name());
    }

    function testSymbol() external view {
        assertEq(USDPPSymbol, usd0PP.symbol());
    }

    function _allowlistAliceAndMintTokens() internal {
        vm.prank(usual);
        usd0PP.mint(alice, 2e18);
        assertEq(usd0PP.totalSupply(), usd0PP.balanceOf(alice));
    }

    function testBlacklistUser() external {
        _allowlistAliceAndMintTokens();
        vm.startPrank(blacklistOperator);
        usd0Token.blacklist(alice);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        usd0Token.blacklist(alice);
        vm.stopPrank();

        vm.assertTrue(usd0Token.isBlacklisted(alice));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Blacklisted.selector));
        usd0PP.transfer(bob, 1e18);

        vm.startPrank(blacklistOperator);
        usd0Token.unBlacklist(alice);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        usd0Token.unBlacklist(alice);
        vm.stopPrank();

        vm.prank(alice);
        usd0PP.transfer(bob, 1e18);
    }

    function testTransferZeroShouldFail() external {
        _allowlistAliceAndMintTokens();
        vm.expectRevert(AmountIsZero.selector);
        vm.prank(alice);
        usd0PP.transfer(bob, 0);
    }

    function testInitializeShouldFailWithNullAddress() public {
        _resetInitializerImplementation(address(usd0PP));
        vm.expectRevert(abi.encodeWithSelector(NullContract.selector));
        usd0PP.initialize(address(0), "USD0", "USD0");
    }

    function testMintShouldNotFail() public {
        vm.prank(usual);
        usd0PP.mint(alice, 2e18);
    }

    // Additional test functions for the Usd0Test contract
    function testUnauthorizedAccessToMintAndBurn() public {
        // Attempt to mint by a non-authorized address
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP.mint(alice, 1e18);

        // Attempt to burn by a non-authorized address
        vm.prank(usual);
        usd0PP.mint(alice, 10e18); // Mint some tokens for Alice
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP.burnFrom(alice, 5e18);
    }

    function testMintNullAddress() public {
        vm.prank(usual);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        usd0PP.mint(address(0), 2e18);
    }

    function testMintAmountZero() public {
        vm.prank(usual);
        vm.expectRevert(AmountIsZero.selector);
        usd0PP.mint(alice, 0);
    }

    function testBurnFromFailIfAmountIsZero() public {
        vm.startPrank(usual);
        usd0PP.mint(alice, 10e18);
        assertEq(usd0PP.balanceOf(alice), 10e18);
        vm.expectRevert(AmountIsZero.selector);
        usd0PP.burnFrom(alice, 0);
        vm.stopPrank();
        assertEq(usd0PP.totalSupply(), 10e18);
        assertEq(usd0PP.balanceOf(alice), 10e18);
    }

    function testBurnFailIfAmountIsZero() public {
        vm.startPrank(usual);
        usd0PP.mint(alice, 10e18);
        assertEq(usd0PP.balanceOf(alice), 10e18);
        vm.expectRevert(AmountIsZero.selector);
        usd0PP.burn(0);
        vm.stopPrank();
        assertEq(usd0PP.totalSupply(), 10e18);
        assertEq(usd0PP.balanceOf(alice), 10e18);
    }

    function testBurnFromFailIfNotAuthorized() public {
        vm.startPrank(usual);
        usd0PP.mint(alice, 10e18);
        assertEq(usd0PP.balanceOf(alice), 10e18);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP.burnFrom(alice, 8e18);
        vm.stopPrank();
        assertEq(usd0PP.totalSupply(), 10e18);
        assertEq(usd0PP.balanceOf(alice), 10e18);
    }

    function testBurnFrom() public {
        _adminGiveUsd0ppBurnRoleTo(usual);
        vm.startPrank(usual);
        usd0PP.mint(alice, 10e18);
        assertEq(usd0PP.balanceOf(alice), 10e18);

        usd0PP.burnFrom(alice, 8e18);

        vm.stopPrank();
        assertEq(usd0PP.totalSupply(), 2e18);
        assertEq(usd0PP.balanceOf(alice), 2e18);
    }

    function testBurnFromFail() public {
        vm.prank(usual);
        usd0PP.mint(alice, 10e18);
        assertEq(usd0PP.balanceOf(alice), 10e18);

        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP.burnFrom(alice, 8e18);

        assertEq(usd0PP.totalSupply(), 10e18);
        assertEq(usd0PP.balanceOf(alice), 10e18);
    }

    function testBurn() public {
        _adminGiveUsd0ppBurnRoleTo(usual);
        vm.startPrank(usual);
        usd0PP.mint(usual, 10e18);

        usd0PP.burn(8e18);

        vm.stopPrank();
        assertEq(usd0PP.balanceOf(usual), 2e18);
    }

    function testBurnFail() public {
        vm.prank(usual);
        usd0PP.mint(alice, 10e18);
        assertEq(usd0PP.balanceOf(alice), 10e18);

        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP.burn(8e18);

        assertEq(usd0PP.totalSupply(), 10e18);
        assertEq(usd0PP.balanceOf(alice), 10e18);
    }

    function testApprove() public {
        assertTrue(usd0PP.approve(alice, 1e18));
        assertEq(usd0PP.allowance(address(this), alice), 1e18);
    }

    function testTransfer() external {
        _allowlistAliceAndMintTokens();
        vm.startPrank(alice);
        usd0PP.transfer(bob, 0.5e18);
        assertEq(usd0PP.balanceOf(bob), 0.5e18);
        assertEq(usd0PP.balanceOf(alice), 1.5e18);
        vm.stopPrank();
    }

    function testTransferAllowlistDisabledSender() public {
        _allowlistAliceAndMintTokens(); // Mint to Alice who is allowlisted
        vm.prank(alice);
        usd0PP.transfer(bob, 0.5e18); // This should succeed because alice is allowlisted
        assertEq(usd0PP.balanceOf(bob), 0.5e18);
        assertEq(usd0PP.balanceOf(alice), 1.5e18);

        // Bob tries to transfer to Carol but is not allowlisted
        vm.startPrank(bob);
        // vm.expectRevert(abi.encodeWithSelector(NotAllowlisted.selector, carol));
        usd0PP.transfer(carol, 0.3e18);
        vm.stopPrank();
    }

    function testTransferAllowlistDisabledRecipient() public {
        _allowlistAliceAndMintTokens(); // Mint to Alice who is allowlisted
        vm.startPrank(alice);
        usd0PP.transfer(bob, 0.5e18); // This should succeed because both are allowlisted
        assertEq(usd0PP.balanceOf(bob), 0.5e18);
        assertEq(usd0PP.balanceOf(alice), 1.5e18);

        // Alice tries to transfer to Carol who is not allowlisted
        // vm.expectRevert(abi.encodeWithSelector(NotAllowlisted.selector, carol));
        usd0PP.transfer(carol, 0.3e18);
        vm.stopPrank();
    }

    function testTransferFrom() external {
        _allowlistAliceAndMintTokens();
        vm.prank(alice);
        usd0PP.approve(address(this), 1e18);
        assertTrue(usd0PP.transferFrom(alice, bob, 0.7e18));
        assertEq(usd0PP.allowance(alice, address(this)), 1e18 - 0.7e18);
        assertEq(usd0PP.balanceOf(alice), 2e18 - 0.7e18);
        assertEq(usd0PP.balanceOf(bob), 0.7e18);
    }

    function testTransferFromWithPermit(uint256 amount) public {
        amount = bound(amount, 100_000_000_000, type(uint128).max);

        vm.startPrank(admin);
        registryAccess.grantRole(USD0PP_MINT, admin);
        usd0PP.mint(alice, amount);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) =
            _getSelfPermitData(address(usd0PP), alice, alicePrivKey, bob, amount, deadline);

        IERC20Permit(address(usd0PP)).permit(alice, bob, amount, deadline, v, r, s);

        vm.stopPrank();
        vm.prank(bob);
        usd0PP.transferFrom(alice, bob, amount);

        assertEq(usd0PP.balanceOf(bob), amount);
        assertEq(usd0PP.balanceOf(alice), 0);
    }

    function testTransferFromAllowlistDisabled() public {
        _allowlistAliceAndMintTokens(); // Mint to Alice who is allowlisted

        vm.prank(alice);
        usd0PP.approve(bob, 2e18); // Alice approves Bob to manage 2 tokens
        // Bob attempts to transfer from Alice to himself
        vm.prank(bob);
        usd0PP.transferFrom(alice, bob, 1e18); // This should succeed because both are allowlisted
        assertEq(usd0PP.balanceOf(bob), 1e18);
        assertEq(usd0PP.balanceOf(alice), 1e18);

        // Bob tries to transfer from Alice again, which is not allowlisted anymore
        vm.prank(bob);
        // vm.expectRevert(abi.encodeWithSelector(NotAllowlisted.selector, alice));
        usd0PP.transferFrom(alice, bob, 0.5e18);
        vm.stopPrank();
    }

    function testTransferFromWorksAllowlistDisabledRecipient() public {
        _allowlistAliceAndMintTokens();

        vm.prank(alice);
        usd0PP.approve(bob, 2e18); // Alice approves Bob to manage 2 tokens
        vm.startPrank(bob);
        usd0PP.approve(bob, 2e18);
        // Bob attempts to transfer from Alice to himself, then to Carol
        usd0PP.transferFrom(alice, bob, 1e18); // This should succeed because both are allowlisted
        assertEq(usd0PP.balanceOf(bob), 1e18);
        assertEq(usd0PP.balanceOf(alice), 1e18);

        //  Bob is allowlisted, but he tries to transfer from himself to Carol, who is not allowlisted
        // vm.expectRevert(abi.encodeWithSelector(NotAllowlisted.selector, carol));
        usd0PP.transferFrom(bob, carol, 0.5e18);
        vm.stopPrank();
    }

    function testPauseUnPause() external {
        _allowlistAliceAndMintTokens();

        vm.prank(pauser);
        usd0PP.pause();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        usd0PP.transfer(bob, 1e18);
        vm.prank(admin);
        usd0PP.unpause();
        vm.prank(alice);
        usd0PP.transfer(bob, 1e18);
    }

    function testPauseUnPauseShouldFailWhenNotAuthorized() external {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP.pause();
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP.unpause();
    }

    function testRoleChangesAffectingMintAndBurn() public {
        // Grant and revoke roles dynamically and test access control
        vm.startPrank(admin);

        registryAccess.grantRole(USD0PP_MINT, carol);
        vm.stopPrank();
        vm.prank(carol);
        usd0PP.mint(alice, 1e18); // Should succeed now that Carol can mint

        vm.prank(admin);
        registryAccess.revokeRole(USD0PP_MINT, carol);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0PP.mint(alice, 1e18); // Should fail now that Carol's mint role is revoked
    }
}
