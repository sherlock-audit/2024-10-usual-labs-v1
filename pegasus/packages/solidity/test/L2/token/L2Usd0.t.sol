// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {L2SetupTest} from "test/L2/L2Setup.t.sol";
import {
    USD0_MINT,
    USD0_BURN,
    CONTRACT_DAO_COLLATERAL,
    USYC,
    PAUSING_CONTRACTS_ROLE
} from "src/constants.sol";
import {RwaMock} from "src/mock/rwaMock.sol";
import {USD0Name, USD0Symbol} from "src/mock/constants.sol";
import {NotAuthorized, Blacklisted, SameValue} from "src/errors.sol";
import {L2Usd0} from "src/L2/token/L2Usd0.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Pausable} from "openzeppelin-contracts/utils/Pausable.sol";

// @title: L2USD0 test contract
// @notice: Contract to test L2USD0 token implementation

contract L2Usd0Test is L2SetupTest {
    L2Usd0 public usd0Token;

    event Blacklist(address account);
    event UnBlacklist(address account);
    event Initialized(uint64 version);

    function setUp() public virtual override {
        uint256 forkId = vm.createFork("arbitrum");
        vm.selectFork(forkId);
        super.setUp();
        usd0Token = stbcToken;
        // give mint role to usual
        _adminGiveUsd0MintRoleTo(usual);
        // give pause role to admin
        _adminGivePauseRoleTo(pauser);
    }

    function _adminGiveUsd0MintRoleTo(address user) internal {
        vm.prank(admin);
        registryAccess.grantRole(USD0_MINT, user);
    }

    function _adminGivePauseRoleTo(address user) internal {
        vm.prank(admin);
        registryAccess.grantRole(PAUSING_CONTRACTS_ROLE, user);
    }

    function _adminGiveUsd0BurnRoleTo(address user) internal {
        vm.prank(admin);
        registryAccess.grantRole(USD0_BURN, user);
    }

    function testName() external view {
        assertEq(USD0Name, usd0Token.name());
    }

    function testSymbol() external view {
        assertEq(USD0Symbol, usd0Token.symbol());
    }

    function _allowlistAliceAndMintTokens() internal {
        vm.prank(usual);
        usd0Token.mint(alice, 2e18);
        assertEq(usd0Token.totalSupply(), usd0Token.balanceOf(alice));
    }

    function testConstructor() public {
        vm.expectEmit();
        emit Initialized(type(uint64).max);
        L2Usd0 l2usd0 = new L2Usd0();
        assertTrue(address(l2usd0) != address(0));
    }

    function testInitializeShouldFailWithNullAddress() public {
        _resetInitializerImplementation(address(usd0Token));
        vm.expectRevert(abi.encodeWithSelector(NullContract.selector));
        L2Usd0(address(usd0Token)).initialize(address(0), "USD0", "USD0");
        vm.expectRevert(abi.encodeWithSelector(InvalidName.selector));
        L2Usd0(address(usd0Token)).initialize(address(0x15), "", "USD0");
        vm.expectRevert(abi.encodeWithSelector(InvalidSymbol.selector));
        L2Usd0(address(usd0Token)).initialize(address(0x15), "USD0", "");
    }

    function testTransferAndCallShouldWork() public {
        _allowlistAliceAndMintTokens();
        assertEq(usd0Token.balanceOf(bob), 0);
        vm.prank(alice);
        usd0Token.transferAndCall(bob, 1e18, "0x");
        assertEq(usd0Token.balanceOf(bob), 1e18);
        assertEq(usd0Token.balanceOf(alice), 1e18);
        // should revert when transferring to non IERC677Receiver contract
        vm.expectRevert();
        vm.prank(alice);
        usd0Token.transferAndCall(address(usd0PP), 1e18, "0x");
    }

    function testMintShouldNotFail() public {
        vm.prank(usual);
        usd0Token.mint(alice, 2e18);
    }

    // Additional test functions for the Usd0Test contract
    function testUnauthorizedAccessToMintAndBurn() public {
        // Attempt to mint by a non-authorized address
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0Token.mint(alice, 1e18);

        // Attempt to burn by a non-authorized address
        vm.prank(usual);
        usd0Token.mint(alice, 10e18); // Mint some tokens for Alice
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0Token.burnFrom(alice, 5e18);
    }

    function testMintNullAddress() public {
        vm.prank(usual);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        usd0Token.mint(address(0), 2e18);
    }

    function testMintAmountZero() public {
        vm.prank(usual);
        vm.expectRevert(AmountIsZero.selector);
        usd0Token.mint(alice, 0);
    }

    function testBurnFromFailIfAmountIsZero() public {
        vm.startPrank(usual);
        usd0Token.mint(alice, 10e18);
        assertEq(usd0Token.balanceOf(alice), 10e18);
        vm.expectRevert(AmountIsZero.selector);
        usd0Token.burnFrom(alice, 0);
        vm.stopPrank();
        assertEq(usd0Token.totalSupply(), 10e18);
        assertEq(usd0Token.balanceOf(alice), 10e18);
    }

    function testBurnFailIfAmountIsZero() public {
        vm.startPrank(usual);
        usd0Token.mint(alice, 10e18);
        assertEq(usd0Token.balanceOf(alice), 10e18);
        vm.expectRevert(AmountIsZero.selector);
        usd0Token.burn(0);
        vm.stopPrank();
        assertEq(usd0Token.totalSupply(), 10e18);
        assertEq(usd0Token.balanceOf(alice), 10e18);
    }

    function testBurnFromFailIfNotAuthorized() public {
        vm.startPrank(usual);
        usd0Token.mint(alice, 10e18);
        assertEq(usd0Token.balanceOf(alice), 10e18);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0Token.burnFrom(alice, 8e18);
        vm.stopPrank();
        assertEq(usd0Token.totalSupply(), 10e18);
        assertEq(usd0Token.balanceOf(alice), 10e18);
    }

    function testBurnFrom() public {
        _adminGiveUsd0BurnRoleTo(usual);
        vm.startPrank(usual);
        usd0Token.mint(alice, 10e18);
        assertEq(usd0Token.balanceOf(alice), 10e18);

        usd0Token.burnFrom(alice, 8e18);

        vm.stopPrank();
        assertEq(usd0Token.totalSupply(), 2e18);
        assertEq(usd0Token.balanceOf(alice), 2e18);
    }

    function testBurnFromFail() public {
        vm.prank(usual);
        usd0Token.mint(alice, 10e18);
        assertEq(usd0Token.balanceOf(alice), 10e18);

        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0Token.burnFrom(alice, 8e18);

        assertEq(usd0Token.totalSupply(), 10e18);
        assertEq(usd0Token.balanceOf(alice), 10e18);
    }

    function testBurn() public {
        _adminGiveUsd0BurnRoleTo(usual);
        vm.startPrank(usual);
        usd0Token.mint(usual, 10e18);

        usd0Token.burn(8e18);

        vm.stopPrank();
        assertEq(usd0Token.balanceOf(usual), 2e18);
    }

    function testBurnFail() public {
        vm.prank(usual);
        usd0Token.mint(alice, 10e18);
        assertEq(usd0Token.balanceOf(alice), 10e18);

        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0Token.burn(8e18);

        assertEq(usd0Token.totalSupply(), 10e18);
        assertEq(usd0Token.balanceOf(alice), 10e18);
    }

    function testApprove() public {
        assertTrue(usd0Token.approve(alice, 1e18));
        assertEq(usd0Token.allowance(address(this), alice), 1e18);
    }

    function testTransfer() external {
        _allowlistAliceAndMintTokens();
        vm.startPrank(alice);
        usd0Token.transfer(bob, 0.5e18);
        assertEq(usd0Token.balanceOf(bob), 0.5e18);
        assertEq(usd0Token.balanceOf(alice), 1.5e18);
        vm.stopPrank();
    }

    function testTransferAllowlistDisabledSender() public {
        _allowlistAliceAndMintTokens(); // Mint to Alice who is allowlisted
        vm.prank(alice);
        usd0Token.transfer(bob, 0.5e18); // This should succeed because alice is allowlisted
        assertEq(usd0Token.balanceOf(bob), 0.5e18);
        assertEq(usd0Token.balanceOf(alice), 1.5e18);

        // Bob tries to transfer to Carol but is not allowlisted
        vm.startPrank(bob);
        // vm.expectRevert(abi.encodeWithSelector(NotAllowlisted.selector, carol));
        usd0Token.transfer(carol, 0.3e18);
        vm.stopPrank();
    }

    function testTransferAllowlistDisabledRecipient() public {
        _allowlistAliceAndMintTokens(); // Mint to Alice who is allowlisted
        vm.startPrank(alice);
        usd0Token.transfer(bob, 0.5e18); // This should succeed because both are allowlisted
        assertEq(usd0Token.balanceOf(bob), 0.5e18);
        assertEq(usd0Token.balanceOf(alice), 1.5e18);

        // Alice tries to transfer to Carol who is not allowlisted
        // vm.expectRevert(abi.encodeWithSelector(NotAllowlisted.selector, carol));
        usd0Token.transfer(carol, 0.3e18);
        vm.stopPrank();
    }

    function testTransferFrom() external {
        _allowlistAliceAndMintTokens();
        vm.prank(alice);
        usd0Token.approve(address(this), 1e18);
        assertTrue(usd0Token.transferFrom(alice, bob, 0.7e18));
        assertEq(usd0Token.allowance(alice, address(this)), 1e18 - 0.7e18);
        assertEq(usd0Token.balanceOf(alice), 2e18 - 0.7e18);
        assertEq(usd0Token.balanceOf(bob), 0.7e18);
    }

    function testTransferFromWithPermit(uint256 amount) public {
        amount = bound(amount, 100_000_000_000, type(uint128).max);

        vm.startPrank(admin);
        registryAccess.grantRole(USD0_MINT, admin);
        usd0Token.mint(alice, amount);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) =
            _getSelfPermitData(address(usd0Token), alice, alicePrivKey, bob, amount, deadline);

        IERC20Permit(address(usd0Token)).permit(alice, bob, amount, deadline, v, r, s);

        vm.stopPrank();
        vm.prank(bob);
        usd0Token.transferFrom(alice, bob, amount);

        assertEq(usd0Token.balanceOf(bob), amount);
        assertEq(usd0Token.balanceOf(alice), 0);
    }

    function testTransferFromAllowlistDisabled() public {
        _allowlistAliceAndMintTokens(); // Mint to Alice who is allowlisted

        vm.prank(alice);
        usd0Token.approve(bob, 2e18); // Alice approves Bob to manage 2 tokens
        // Bob attempts to transfer from Alice to himself
        vm.prank(bob);
        usd0Token.transferFrom(alice, bob, 1e18); // This should succeed because both are allowlisted
        assertEq(usd0Token.balanceOf(bob), 1e18);
        assertEq(usd0Token.balanceOf(alice), 1e18);

        // Bob tries to transfer from Alice again, which is not allowlisted anymore
        vm.prank(bob);
        // vm.expectRevert(abi.encodeWithSelector(NotAllowlisted.selector, alice));
        usd0Token.transferFrom(alice, bob, 0.5e18);
        vm.stopPrank();
    }

    function testTransferFromWorksAllowlistDisabledRecipient() public {
        _allowlistAliceAndMintTokens();

        vm.prank(alice);
        usd0Token.approve(bob, 2e18); // Alice approves Bob to manage 2 tokens
        vm.startPrank(bob);
        usd0Token.approve(bob, 2e18);
        // Bob attempts to transfer from Alice to himself, then to Carol
        usd0Token.transferFrom(alice, bob, 1e18); // This should succeed because both are allowlisted
        assertEq(usd0Token.balanceOf(bob), 1e18);
        assertEq(usd0Token.balanceOf(alice), 1e18);

        //  Bob is allowlisted, but he tries to transfer from himself to Carol, who is not allowlisted
        // vm.expectRevert(abi.encodeWithSelector(NotAllowlisted.selector, carol));
        usd0Token.transferFrom(bob, carol, 0.5e18);
        vm.stopPrank();
    }

    function testPauseUnPause() external {
        _allowlistAliceAndMintTokens();

        vm.prank(pauser);
        usd0Token.pause();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        usd0Token.transfer(bob, 1e18);
        vm.prank(admin);
        usd0Token.unpause();
        vm.prank(alice);
        usd0Token.transfer(bob, 1e18);
    }

    function testPauseUnPauseShouldFailWhenNotAuthorized() external {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0Token.pause();
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0Token.unpause();
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
        usd0Token.transfer(bob, 1e18);

        vm.startPrank(blacklistOperator);
        usd0Token.unBlacklist(alice);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        usd0Token.unBlacklist(alice);
        vm.stopPrank();

        vm.prank(alice);
        usd0Token.transfer(bob, 1e18);
    }

    function testBlacklistShouldRevertIfAddressIsZero() external {
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        usd0Token.blacklist(address(0));
    }

    function testBlacklistAndUnBlacklistEmitsEvents() external {
        _allowlistAliceAndMintTokens();
        vm.startPrank(blacklistOperator);
        vm.expectEmit();
        emit Blacklist(alice);
        usd0Token.blacklist(alice);

        vm.expectEmit();
        emit UnBlacklist(alice);
        usd0Token.unBlacklist(alice);
        vm.stopPrank();
    }

    function testOnlyBlacklisterCanUseBlacklist(address user) external {
        vm.assume(user != blacklistOperator);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0Token.blacklist(alice);

        vm.prank(blacklistOperator);
        usd0Token.blacklist(alice);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0Token.unBlacklist(alice);
    }

    function testRoleChangesAffectingMintAndBurn() public {
        // Grant and revoke roles dynamically and test access control
        vm.startPrank(admin);

        registryAccess.grantRole(USD0_MINT, carol);
        vm.stopPrank();
        vm.prank(carol);
        usd0Token.mint(alice, 1e18); // Should succeed now that Carol can mint

        vm.prank(admin);
        registryAccess.revokeRole(USD0_MINT, carol);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0Token.mint(alice, 1e18); // Should fail now that Carol's mint role is revoked
    }
}
