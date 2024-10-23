// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SetupTest} from "test/setup.t.sol";
import {USD0_MINT, CONTRACT_DAO_COLLATERAL, USYC} from "src/constants.sol";
import {USYC_PRICE_FEED_MAINNET} from "src/mock/constants.sol";
import {RwaMock} from "src/mock/rwaMock.sol";
import {IRwaMock} from "src/interfaces/token/IRwaMock.sol";
import {IAggregator} from "src/interfaces/oracles/IAggregator.sol";
import {USD0Name, USD0Symbol} from "src/mock/constants.sol";
import {NotAuthorized, Blacklisted, SameValue, AmountExceedBacking} from "src/errors.sol";
import {Usd0} from "src/token/Usd0.sol";
import {Usd0Harness} from "src/mock/token/Usd0Harness.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Pausable} from "openzeppelin-contracts/utils/Pausable.sol";

// @title: USD0 test contract
// @notice: Contract to test USD0 token implementation

contract Usd0Test is SetupTest {
    Usd0 public usd0Token;

    event Blacklist(address account);
    event UnBlacklist(address account);

    function setUp() public virtual override {
        uint256 forkId = vm.createFork("eth");
        vm.selectFork(forkId);
        super.setUp();
        usd0Token = stbcToken;
        vm.startPrank(admin);
        classicalOracle.initializeTokenOracle(USYC, USYC_PRICE_FEED_MAINNET, 7 days, false);
        tokenMapping.addUsd0Rwa(USYC);
        vm.stopPrank();

        deal(USYC, treasury, type(uint128).max);
    }

    function setupCreationRwa2(uint8 decimals) public returns (RwaMock) {
        rwaFactory.createRwa("Hashnote US Yield Coin 2", "USYC2", decimals);
        address rwa2 = rwaFactory.getRwaFromSymbol("USYC2");
        vm.label(rwa2, "USYC2 Mock");

        _whitelistRWA(rwa2, alice);
        _whitelistRWA(rwa2, address(daoCollateral));
        _whitelistRWA(rwa2, treasury);
        _linkSTBCToRwa(IRwaMock(rwa2));
        // add mock oracle for rwa token
        whitelistPublisher(address(rwa2), address(usd0Token));
        _setupBucket(rwa2, address(usd0Token));
        _setOraclePrice(rwa2, 10 ** decimals);

        return RwaMock(rwa2);
    }

    function testName() external view {
        assertEq(USD0Name, usd0Token.name());
    }

    function testSymbol() external view {
        assertEq(USD0Symbol, usd0Token.symbol());
    }

    function allowlistAliceAndMintTokens() public {
        vm.prank(address(registryContract.getContract(CONTRACT_DAO_COLLATERAL)));
        usd0Token.mint(alice, 2e18);
        assertEq(usd0Token.totalSupply(), usd0Token.balanceOf(alice));
    }

    function testInitializeShouldFailWithNullAddress() public {
        _resetInitializerImplementation(address(usd0Token));
        vm.expectRevert(abi.encodeWithSelector(NullContract.selector));
        Usd0Harness(address(usd0Token)).initialize(address(0), "USD0", "USD0");
    }

    function testConstructor() public {
        Usd0 usd0 = new Usd0();
        assertTrue(address(usd0) != address(0));
    }

    function testAnyoneCanCreateUsd0() public {
        Usd0Harness stbcToken = new Usd0Harness();
        _resetInitializerImplementation(address(stbcToken));
        Usd0Harness(address(stbcToken)).initialize(address(registryContract), USD0Name, USD0Symbol);
        Usd0Harness(address(stbcToken)).initializeV1(registryContract);
        Usd0(address(stbcToken)).initializeV2();
        assertTrue(address(stbcToken) != address(0));
    }

    function testMintShouldNotFail() public {
        address minter = address(registryContract.getContract(CONTRACT_DAO_COLLATERAL));
        vm.prank(minter);
        usd0Token.mint(alice, 2e18);
    }

    function testMintShouldFailDueToNoBacking() public {
        deal(USYC, treasury, 0);
        _adminGiveUsd0MintRoleTo(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AmountExceedBacking.selector));
        usd0Token.mint(alice, 2e18);
    }

    // Additional test functions for the Usd0Test contract

    function testUnauthorizedAccessToMintAndBurn() public {
        // Attempt to mint by a non-authorized address
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0Token.mint(alice, 1e18);

        // Attempt to burn by a non-authorized address
        vm.prank(address(registryContract.getContract(CONTRACT_DAO_COLLATERAL)));
        usd0Token.mint(alice, 10e18); // Mint some tokens for Alice
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0Token.burnFrom(alice, 5e18);
    }

    function testRoleChangesAffectingMintAndTreasuryNotBackedFail() public {
        deal(USYC, treasury, 0);
        // Grant and revoke roles dynamically and test access control
        _adminGiveUsd0MintRoleTo(carol);
        vm.stopPrank();
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(AmountExceedBacking.selector));
        usd0Token.mint(alice, 1e18); // Should fail now since there is no USYC in the treasury
    }

    function testMintNullAddress() public {
        vm.prank(address(registryContract.getContract(CONTRACT_DAO_COLLATERAL)));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        usd0Token.mint(address(0), 2e18);
    }

    function testMintAmountZero() public {
        vm.prank(address(registryContract.getContract(CONTRACT_DAO_COLLATERAL)));
        vm.expectRevert(AmountIsZero.selector);
        usd0Token.mint(alice, 0);
    }

    function testBurnFromDoesNotFailIfNotAuthorized() public {
        vm.prank(address(registryContract.getContract(CONTRACT_DAO_COLLATERAL)));
        usd0Token.mint(alice, 10e18);
        assertEq(usd0Token.balanceOf(alice), 10e18);
        vm.prank(admin);

        vm.prank(address(registryContract.getContract(CONTRACT_DAO_COLLATERAL)));
        // vm.expectRevert(abi.encodeWithSelector(NotAllowlisted.selector, alice));
        usd0Token.burnFrom(alice, 8e18);

        assertEq(usd0Token.totalSupply(), 2e18);
        assertEq(usd0Token.balanceOf(alice), 2e18);
    }

    function testBurnFrom() public {
        vm.startPrank(address(registryContract.getContract(CONTRACT_DAO_COLLATERAL)));
        usd0Token.mint(alice, 10e18);
        assertEq(usd0Token.balanceOf(alice), 10e18);

        usd0Token.burnFrom(alice, 8e18);

        assertEq(usd0Token.totalSupply(), 2e18);
        assertEq(usd0Token.balanceOf(alice), 2e18);
    }

    function testBurnFromFail() public {
        vm.prank(address(registryContract.getContract(CONTRACT_DAO_COLLATERAL)));
        usd0Token.mint(alice, 10e18);
        assertEq(usd0Token.balanceOf(alice), 10e18);

        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usd0Token.burnFrom(alice, 8e18);

        assertEq(usd0Token.totalSupply(), 10e18);
        assertEq(usd0Token.balanceOf(alice), 10e18);
    }

    function testBurn() public {
        vm.startPrank(address(registryContract.getContract(CONTRACT_DAO_COLLATERAL)));
        usd0Token.mint(address(registryContract.getContract(CONTRACT_DAO_COLLATERAL)), 10e18);

        usd0Token.burn(8e18);

        assertEq(
            usd0Token.balanceOf(address(registryContract.getContract(CONTRACT_DAO_COLLATERAL))),
            2e18
        );
    }

    function testBurnFail() public {
        vm.prank(address(registryContract.getContract(CONTRACT_DAO_COLLATERAL)));
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
        allowlistAliceAndMintTokens();
        vm.startPrank(alice);
        usd0Token.transfer(bob, 0.5e18);
        assertEq(usd0Token.balanceOf(bob), 0.5e18);
        assertEq(usd0Token.balanceOf(alice), 1.5e18);
        vm.stopPrank();
    }

    function testTransferAllowlistDisabledSender() public {
        allowlistAliceAndMintTokens(); // Mint to Alice who is allowlisted
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
        allowlistAliceAndMintTokens(); // Mint to Alice who is allowlisted
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
        allowlistAliceAndMintTokens();
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
        allowlistAliceAndMintTokens(); // Mint to Alice who is allowlisted

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
        allowlistAliceAndMintTokens();

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
        allowlistAliceAndMintTokens();

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
        allowlistAliceAndMintTokens();
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
        allowlistAliceAndMintTokens();
        vm.startPrank(blacklistOperator);
        vm.expectEmit();
        emit Blacklist(alice);
        usd0Token.blacklist(alice);

        vm.expectEmit();
        emit UnBlacklist(alice);
        usd0Token.unBlacklist(alice);
    }

    function testOnlyAdminCanUseBlacklist(address user) external {
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

    function testMintingWithBacking() external {
        _adminGiveUsd0MintRoleTo(alice);
        vm.prank(alice);
        usd0Token.mint(alice, 100_000e18); // Since we put USYC in treasury, we should be able to mint
    }

    function testMintingWithBackingNotDaoCollateralAndTwoRwasFuzz(uint256 amount, uint256 decimals)
        external
    {
        amount = bound(amount, 1, type(uint128).max);
        decimals = bound(decimals, 1, 27);
        RwaMock rwa2 = setupCreationRwa2(uint8(decimals));
        deal(address(rwa2), treasury, amount * (10 ** decimals));

        _adminGiveUsd0MintRoleTo(alice);
        vm.prank(alice);
        usd0Token.mint(alice, 2 * amount);
        assertEq(usd0Token.balanceOf(alice), 2 * amount);
    }

    function testMintingWithBackingNotDaoCollateralAndTwoRwasRevertFuzz(
        uint256 amount,
        uint256 decimals
    ) external {
        amount = bound(amount, 1, type(uint128).max);
        decimals = bound(decimals, 1, 27);
        RwaMock rwa2 = setupCreationRwa2(uint8(decimals));
        deal(USYC, treasury, 0);
        deal(address(rwa2), treasury, amount * (10 ** decimals));

        _adminGiveUsd0MintRoleTo(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AmountExceedBacking.selector));
        usd0Token.mint(alice, 3 * amount * 1e18);
    }

    function testMintingWithBackingAndTwoRwasRevert() external {
        RwaMock rwa2 = setupCreationRwa2(12);
        deal(USYC, treasury, 0);
        deal(address(rwa2), treasury, 100_000e12);

        _adminGiveUsd0MintRoleTo(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AmountExceedBacking.selector));
        usd0Token.mint(alice, 210_000e18);
    }

    function testMintingWithBackingDaoCollateral() external {
        _adminGiveUsd0MintRoleTo(alice);
        vm.prank(address(registryContract.getContract(CONTRACT_DAO_COLLATERAL)));
        usd0Token.mint(alice, 100_000e18); // Since we put USYC in treasury, we should be able to mint
    }

    function testMintingWithBackingDaoCollateralRevert() external {
        deal(USYC, treasury, 0);
        _adminGiveUsd0MintRoleTo(alice);
        vm.prank(address(registryContract.getContract(CONTRACT_DAO_COLLATERAL)));
        vm.expectRevert(abi.encodeWithSelector(AmountExceedBacking.selector));
        usd0Token.mint(alice, 200_000e18);
    }

    function testRWAPriceDropMintFail() external {
        deal(USYC, treasury, 100_000e6);
        _adminGiveUsd0MintRoleTo(alice);

        vm.prank(address(registryContract.getContract(CONTRACT_DAO_COLLATERAL)));
        usd0Token.mint(alice, 100_000e18); // Since we put USYC in treasury, we should be able to mint

        // Mock USYC PriceFeed
        uint80 roundId = 1;
        int256 answer = 0.9e8;
        uint256 startedAt = block.timestamp - 1;
        uint256 updatedAt = block.timestamp - 1;
        uint80 answeredInRound = 1;
        vm.mockCall(
            USYC_PRICE_FEED_MAINNET,
            abi.encodeWithSelector(IAggregator.latestRoundData.selector),
            abi.encode(roundId, answer, startedAt, updatedAt, answeredInRound)
        );

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AmountExceedBacking.selector));
        usd0Token.mint(alice, 1); // Since the price drops, we should not be able to mint
    }

    function testFuzzingRWAPriceChange(uint256 oraclePriceReturn) external {
        deal(USYC, treasury, 100_000e6);
        // Oracle return price on 8 decimals
        oraclePriceReturn = bound(oraclePriceReturn, 0.1e8, 10e8);

        _adminGiveUsd0MintRoleTo(alice);

        vm.prank(address(registryContract.getContract(CONTRACT_DAO_COLLATERAL)));
        usd0Token.mint(alice, 100_000e18); // Since we put USYC in treasury, we should be able to mint

        // Mock USYC PriceFeed
        uint80 roundId = 1;
        int256 answer = int256(oraclePriceReturn);
        uint256 startedAt = block.timestamp - 1;
        uint256 updatedAt = block.timestamp - 1;
        uint80 answeredInRound = 1;
        vm.mockCall(
            USYC_PRICE_FEED_MAINNET,
            abi.encodeWithSelector(IAggregator.latestRoundData.selector),
            abi.encode(roundId, answer, startedAt, updatedAt, answeredInRound)
        );

        if (oraclePriceReturn <= 1e8) {
            vm.prank(alice);
            vm.expectRevert(abi.encodeWithSelector(AmountExceedBacking.selector));
            usd0Token.mint(alice, 1); // Since the price drops, we should not be able to mint
        } else {
            vm.prank(alice);
            usd0Token.mint(alice, 1);
        }
    }

    function _adminGiveUsd0MintRoleTo(address user) internal {
        vm.prank(admin);
        registryAccess.grantRole(USD0_MINT, user);
    }
}
