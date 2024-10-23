// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";

import {ONE_MONTH_IN_SECONDS} from "src/mock/constants.sol";

import {YIELD_PRECISION} from "src/constants.sol";
import {SetupTest} from "../setup.t.sol";
import {ERC165Checker} from "openzeppelin-contracts/utils/introspection/ERC165Checker.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {UsualX} from "src/vaults/UsualX.sol";
import {
    NullContract,
    NullAddress,
    AmountTooBig,
    Blacklisted,
    SameValue,
    ZeroYieldAmount,
    StartTimeNotInFuture,
    EndTimeNotAfterStartTime,
    InsufficientAssetsForYield,
    CurrentTimeBeforePeriodFinish,
    StartTimeBeforePeriodFinish
} from "src/errors.sol";

import {
    BASIS_POINT_BASE,
    CONTRACT_USUAL,
    BLACKLIST_ROLE,
    CONTRACT_DISTRIBUTION_MODULE,
    MAX_25_PERCENT_WITHDRAW_FEE,
    USUALSymbol,
    USUALName,
    USUALXSymbol,
    USUALXName,
    USUALX_WITHDRAW_FEE
} from "src/constants.sol";

contract UsualXIntegrationTest is SetupTest, UsualX {
    address public constant distributionModuleAddress = address(0x56897845);

    function setUp() public virtual override {
        uint256 forkId = vm.createFork("eth");
        vm.selectFork(forkId);
        super.setUp();
        vm.deal(alice, 1 ether);
        //set CONTRACT_DISTRIBUTION_MODULE to be a random address
        vm.startPrank(admin);
        registryContract.setContract(CONTRACT_DISTRIBUTION_MODULE, distributionModuleAddress);
        vm.stopPrank();
    }

    bytes32 constant YIELD_DATA_STORAGE_SLOT =
        0x9a66cc64068466ca9954f77b424b83884332fd82446a2cbd356234cdc6547600;

    // Helper functions to read YieldDataStorage fields
    function getTotalDeposits() internal view returns (uint256) {
        return uint256(vm.load(address(usualX), YIELD_DATA_STORAGE_SLOT));
    }

    function getPeriodStart() internal view returns (uint256) {
        return uint256(vm.load(address(usualX), bytes32(uint256(YIELD_DATA_STORAGE_SLOT) + 2)));
    }

    function getPeriodFinish() internal view returns (uint256) {
        return uint256(vm.load(address(usualX), bytes32(uint256(YIELD_DATA_STORAGE_SLOT) + 3)));
    }

    function getLastUpdateTime() internal view returns (uint256) {
        return uint256(vm.load(address(usualX), bytes32(uint256(YIELD_DATA_STORAGE_SLOT) + 4)));
    }

    function getIsActive() internal view returns (bool) {
        return uint256(vm.load(address(usualX), bytes32(uint256(YIELD_DATA_STORAGE_SLOT) + 5))) == 1;
    }

    function _calculateTotalWithdraw(uint256 withdrawAmount) internal pure returns (uint256) {
        return withdrawAmount + _calculateFee(withdrawAmount);
    }

    function _calculateFee(uint256 withdrawAmount) internal pure returns (uint256) {
        return
            Math.mulDiv(withdrawAmount, USUALX_WITHDRAW_FEE, BASIS_POINT_BASE, Math.Rounding.Floor);
    }

    function testName() external view {
        assertEq(USUALXName, usualX.name());
    }

    function testSymbol() external view {
        assertEq(USUALXSymbol, usualX.symbol());
    }

    function testUsualErc20Compliance() external view {
        ERC165Checker.supportsInterface(address(usualX), type(IERC20).interfaceId);
    }

    function mintTokensToAlice() public {
        vm.prank(admin);
        usualToken.mint(alice, 2e18);
        usualX.deposit(2e18, alice);
        assertEq(usualX.totalSupply(), usualX.balanceOf(alice));
    }

    function testCreationOfUsualXToken() public {
        _resetInitializerImplementation(address(usualX));
        usualX.initialize(address(registryContract), USUALX_WITHDRAW_FEE, USUALXName, USUALXSymbol);
    }

    function testInitializeShouldFailWithNullAddress() public {
        _resetInitializerImplementation(address(usualX));
        //
        vm.expectRevert(abi.encodeWithSelector(NullContract.selector));
        usualX.initialize(address(0), USUALX_WITHDRAW_FEE, USUALXName, USUALXSymbol);
    }

    function testInitializeShouldFailWithAmountTooBigWithdrawFee() public {
        _resetInitializerImplementation(address(usualX));
        vm.expectRevert(abi.encodeWithSelector(AmountTooBig.selector));
        usualX.initialize(address(registryContract), 2501, USUALXName, USUALXSymbol);
    }

    function testPreviewFunctions() public {
        uint256 depositAmount = 100e18;
        vm.prank(admin);
        usualToken.mint(alice, depositAmount);

        vm.startPrank(alice);
        usualToken.approve(address(usualX), depositAmount);
        usualX.deposit(depositAmount, alice);

        // Test withdraw
        uint256 withdrawAmount = 50e18;
        uint256 expectedSharesWithdraw = usualX.previewWithdraw(withdrawAmount);
        uint256 actualSharesWithdraw = usualX.withdraw(withdrawAmount, alice, alice);
        assertEq(
            expectedSharesWithdraw,
            actualSharesWithdraw,
            "Withdraw: Burned shares should match preview"
        );

        // Test redeem
        uint256 redeemShares = 25e18;
        uint256 expectedAssetsRedeem = usualX.previewRedeem(redeemShares);
        uint256 actualAssetsRedeem = usualX.redeem(redeemShares, alice, alice);
        assertEq(
            expectedAssetsRedeem,
            actualAssetsRedeem,
            "Redeem: Withdrawn assets should match preview"
        );
        vm.stopPrank();

        // Test deposit
        uint256 depositAmount2 = 30e18;
        vm.prank(admin);
        usualToken.mint(alice, depositAmount2);

        vm.startPrank(alice);
        usualToken.approve(address(usualX), depositAmount2);
        uint256 expectedSharesDeposit = usualX.previewDeposit(depositAmount2);
        uint256 actualSharesDeposit = usualX.deposit(depositAmount2, alice);
        vm.stopPrank();
        assertEq(
            expectedSharesDeposit,
            actualSharesDeposit,
            "Deposit: Minted shares should match preview"
        );

        // Test mint
        uint256 mintShares = 15e18;
        uint256 expectedAssetsMint = usualX.previewMint(mintShares);
        vm.startPrank(alice);
        usualToken.approve(address(usualX), expectedAssetsMint);
        uint256 actualAssetsMint = usualX.mint(mintShares, alice);
        vm.stopPrank();
        assertEq(
            expectedAssetsMint, actualAssetsMint, "Mint: Deposited assets should match preview"
        );
    }

    function testDeposit() public {
        uint256 depositAmount = 10e18;
        vm.startPrank(admin);
        usualToken.mint(alice, depositAmount);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), depositAmount);
        uint256 sharesMinted = usualX.deposit(depositAmount, alice);
        vm.stopPrank();

        assertEq(usualX.balanceOf(alice), sharesMinted, "Incorrect shares minted");
        assertEq(usualX.totalAssets(), depositAmount, "Incorrect total assets");
        assertEq(
            usualToken.balanceOf(address(usualX)), depositAmount, "Incorrect vault token balance"
        );
    }

    function testDepositWithPermit(uint256 amount) public {
        amount = bound(amount, 1e18, 1_000_000e18);

        deal(address(usualToken), alice, amount);

        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(usualToken), alice, alicePrivKey, address(usualX), amount, deadline
        );
        vm.prank(alice);
        usualX.depositWithPermit(amount, alice, deadline, v, r, s);

        assertEq(usualX.balanceOf(alice), amount, "Incorrect shares minted");
        assertEq(usualX.totalAssets(), amount, "Incorrect total assets");
        assertEq(usualToken.balanceOf(address(usualX)), amount, "Incorrect vault token balance");
    }

    function testDepositWithPermitFailsWithInvalidPermit() public {
        uint256 depositAmount = 10e18;

        deal(address(usualToken), alice, depositAmount);

        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(usualToken), alice, alicePrivKey, address(usualX), depositAmount, deadline
        );

        vm.startPrank(alice);

        // bad v
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usualX), 0, depositAmount
            )
        );
        usualX.depositWithPermit(depositAmount, alice, deadline, 0, r, s);
        vm.stopPrank();

        // bad r
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usualX), 0, depositAmount
            )
        );
        usualX.depositWithPermit(depositAmount, alice, deadline, v, bytes32(0), s);
        vm.stopPrank();

        // bad s
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usualX), 0, depositAmount
            )
        );
        usualX.depositWithPermit(depositAmount, alice, deadline, v, r, bytes32(0));
        vm.stopPrank();

        // bad deadline
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usualX), 0, depositAmount
            )
        );
        usualX.depositWithPermit(depositAmount, alice, deadline + 1, v, r, s);
        vm.stopPrank();
    }

    function testWithdraw() public {
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 50e18;

        // Initial deposit
        vm.startPrank(admin);
        usualToken.mint(alice, depositAmount);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), depositAmount);
        usualX.deposit(depositAmount, alice);

        uint256 initialTotalAssets = usualX.totalAssets();
        uint256 initialAliceBalance = usualToken.balanceOf(alice);

        assertEq(usualX.totalAssets(), depositAmount, "Total assets should match deposit amount");
        assertEq(
            usualToken.balanceOf(address(usualX)),
            depositAmount,
            "Vault token balance should match deposit amount"
        );

        // Calculate the expected shares burned
        uint256 expectedSharesBurned = usualX.previewWithdraw(withdrawAmount);

        // Perform withdrawal
        uint256 sharesBurned = usualX.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        // Check that the shares burned correspond to the total amount withdrawn (including fee)
        assertEq(sharesBurned, expectedSharesBurned, "Shares burned should match preview");
        // Calculate total assets needed, including fee
        uint256 assetsWithFee = (withdrawAmount + _calculateFee(withdrawAmount));
        assertEq(
            assetsWithFee,
            withdrawAmount + (withdrawAmount * USUALX_WITHDRAW_FEE) / BASIS_POINT_BASE,
            "Fee should be 5% of withdrawn amount"
        );

        // Assertions
        assertEq(
            usualToken.balanceOf(alice),
            initialAliceBalance + withdrawAmount,
            "User should receive exact requested amount"
        );
        assertEq(
            usualX.totalAssets(),
            initialTotalAssets - assetsWithFee,
            "Total assets should decrease by withdrawn amount plus fee"
        );

        // Verify that totalDeposited in the vault has decreased by the full amount (withdraw + fee)
        uint256 expectedTotalDeposited = initialTotalAssets - assetsWithFee;
        assertEq(
            usualX.totalAssets(),
            expectedTotalDeposited,
            "Total deposited should decrease by withdraw amount plus fee"
        );
    }

    function testWithdrawAboveMaxFails() public {
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 100e18;

        // Initial deposit
        vm.startPrank(admin);
        usualToken.mint(alice, depositAmount);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), depositAmount);
        usualX.deposit(depositAmount, alice);
        uint256 maxAssetsAliceCanWithdraw = usualX.maxWithdraw(alice);
        // Perform withdrawal
        assertGt(
            withdrawAmount, maxAssetsAliceCanWithdraw, "Trying to withdraw more than max allowed"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626ExceededMaxWithdraw.selector,
                alice,
                withdrawAmount,
                maxAssetsAliceCanWithdraw
            )
        );
        usualX.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();
    }

    function testRedeemAboveMaxFails() public {
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 101e18;

        // Initial deposit
        vm.startPrank(admin);
        usualToken.mint(alice, depositAmount);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), depositAmount);
        usualX.deposit(depositAmount, alice);
        uint256 maxSharesAliceCanRedeem = usualX.maxRedeem(alice);
        // Perform withdrawal
        assertGt(withdrawAmount, maxSharesAliceCanRedeem, "Trying to redeem more than max allowed");
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626ExceededMaxRedeem.selector, alice, withdrawAmount, maxSharesAliceCanRedeem
            )
        );
        usualX.redeem(withdrawAmount, alice, alice);
        vm.stopPrank();
    }

    function testPrecisionAt1BPS() public pure {
        uint256[] memory testAmounts = new uint256[](5);
        testAmounts[0] = 1; // 1 wei
        testAmounts[1] = 10; // 100 wei
        testAmounts[2] = 100; // 1 ether
        testAmounts[3] = 1e20; // 100 ether

        uint256 maxWithdrawWithFee = (2 ** 256 - 1) - _calculateFee(2 ** 256 - 1);
        testAmounts[4] = maxWithdrawWithFee; // max uint256

        for (uint256 i = 0; i < testAmounts.length; i++) {
            uint256 withdrawAmount = testAmounts[i];
            uint256 calculatedFee = _calculateFee(withdrawAmount);
            uint256 totalWithdraw = withdrawAmount + calculatedFee;
            uint256 directFee = totalWithdraw - withdrawAmount;

            if (withdrawAmount >= 100) {
                // For amounts >= 10000, we expect no precision loss
                assertEq(calculatedFee, directFee, "Fee calculations should match exactly");
            } else {
                // For amounts < 10000, there might be a difference of at most 1 wei
                assertEq(directFee, 0, "Fee calculations should match exactly");
            }
        }
    }

    function testYieldDistribution() public {
        uint256 initialDeposit = 100e18;
        uint256 yieldAmount = 24e18;
        vm.prank(admin);
        usualToken.mint(alice, initialDeposit);

        vm.startPrank(alice);
        usualToken.approve(address(usualX), initialDeposit);
        usualX.deposit(initialDeposit, alice);
        vm.stopPrank();

        vm.prank(admin);
        usualToken.mint(address(usualX), yieldAmount);

        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yieldAmount, startTime, endTime);

        vm.warp(startTime); // Warp to start of yield period
        uint256 initialTotalAssets = usualX.totalAssets();

        vm.warp(endTime + 1); // Warp to end of yield period
        uint256 finalTotalAssets = usualX.totalAssets();

        assertEq(finalTotalAssets, initialTotalAssets + yieldAmount, "Incorrect final total assets");
    }

    function testMultiUserYieldDistribution() public {
        uint256 aliceDeposit = 50e18;
        uint256 bobDeposit = 100e18;
        uint256 yieldAmount = 24e18;

        vm.startPrank(admin);
        usualToken.mint(alice, aliceDeposit);
        usualToken.mint(bob, bobDeposit);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), aliceDeposit);
        usualX.deposit(aliceDeposit, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        usualToken.approve(address(usualX), bobDeposit);
        usualX.deposit(bobDeposit, bob);
        vm.stopPrank();

        vm.prank(admin);
        usualToken.mint(address(usualX), yieldAmount);

        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yieldAmount, startTime, endTime);

        vm.warp(endTime);

        uint256 totalInitialDeposit = aliceDeposit + bobDeposit;
        uint256 totalFinalAssets = totalInitialDeposit + yieldAmount;

        //NOTE: convertToAssets rounds down by erc4626 standard
        uint256 expectedAliceAssets = (aliceDeposit * totalFinalAssets) / totalInitialDeposit;
        uint256 expectedBobAssets = (bobDeposit * totalFinalAssets) / totalInitialDeposit;

        uint256 aliceAssets = usualX.convertToAssets(usualX.balanceOf(alice));
        uint256 bobAssets = usualX.convertToAssets(usualX.balanceOf(bob));

        assertApproxEqAbs(aliceAssets, expectedAliceAssets, 1, "Incorrect assets for Alice");
        assertApproxEqAbs(bobAssets, expectedBobAssets, 1, "Incorrect assets for Bob");
        assertApproxEqAbs(
            aliceAssets * 2, bobAssets, 1, "Bob should have exactly twice the assets of Alice"
        );
    }

    function testMultipleYieldPeriods() public {
        uint256 initialDeposit = 1000e18;
        uint256 yield1 = 100e18;
        uint256 yield2 = 50e18;

        // Initial deposit
        vm.startPrank(admin);
        usualToken.mint(alice, initialDeposit);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), initialDeposit);
        usualX.deposit(initialDeposit, alice);
        vm.stopPrank();

        // First yield period
        vm.prank(admin);
        usualToken.mint(address(usualX), yield1);

        uint256 startTime1 = block.timestamp + 1 hours;
        uint256 endTime1 = startTime1 + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield1, startTime1, endTime1);

        vm.warp(endTime1);

        // Second yield period
        vm.prank(admin);
        usualToken.mint(address(usualX), yield2);

        uint256 startTime2 = endTime1;
        uint256 endTime2 = startTime2 + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield2, startTime2, endTime2);

        vm.warp(endTime2);

        uint256 expectedTotalAssets = initialDeposit + yield1 + yield2;
        assertEq(
            usualX.totalAssets(),
            expectedTotalAssets,
            "Total assets should include both yield periods"
        );

        uint256 aliceAssets = usualX.convertToAssets(usualX.balanceOf(alice));
        assertApproxEqAbs(
            aliceAssets, expectedTotalAssets, 1, "Alice's assets should equal total assets"
        );
    }

    function testMultipleYieldOverlappingPeriods() public {
        uint256 initialDeposit = 1000e18;
        uint256 yield1 = 100e18;
        uint256 yield2 = 50e18;

        // Initial deposit
        vm.startPrank(admin);
        usualToken.mint(alice, initialDeposit);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), initialDeposit);
        usualX.deposit(initialDeposit, alice);
        vm.stopPrank();

        // First yield period
        vm.prank(admin);
        usualToken.mint(address(usualX), yield1);
        vm.warp(0.5 days);

        uint256 startTime1 = block.timestamp + 1 hours;
        uint256 endTime1 = startTime1 + 1 days;
        //log the timestamp
        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield1, startTime1, endTime1);
        vm.warp(0.5 days);
        // Second yield period
        vm.prank(admin);
        usualToken.mint(address(usualX), yield2);
        uint256 startTime2 = endTime1;
        uint256 endTime2 = startTime2 + 1 days;
        //log the timestamp
        vm.prank(distributionModuleAddress);
        //expect revert with reason CurrentTimeBeforePeriodFinish
        vm.expectRevert(abi.encodeWithSelector(CurrentTimeBeforePeriodFinish.selector));
        usualX.startYieldDistribution(yield2, startTime2, endTime2);
    }

    function testYieldWithIntermediateDeposits() public {
        uint256 initialDeposit = 1000e18;
        uint256 yield1 = 100e18;
        uint256 bobDeposit = 500e18;
        uint256 yield2 = 50e18;

        // Alice's initial deposit
        vm.startPrank(admin);
        usualToken.mint(alice, initialDeposit);
        usualToken.mint(bob, bobDeposit);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), initialDeposit);
        usualX.deposit(initialDeposit, alice);
        vm.stopPrank();

        // First yield period
        vm.prank(admin);
        usualToken.mint(address(usualX), yield1);

        uint256 startTime1 = block.timestamp + 1 hours;
        uint256 endTime1 = startTime1 + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield1, startTime1, endTime1);

        vm.warp(startTime1 + 12 hours);

        // Bob deposits midway through first yield period
        vm.startPrank(bob);
        usualToken.approve(address(usualX), bobDeposit);
        usualX.deposit(bobDeposit, bob);
        vm.stopPrank();

        vm.warp(endTime1);

        // Second yield period
        vm.prank(admin);
        usualToken.mint(address(usualX), yield2);

        uint256 startTime2 = endTime1;
        uint256 endTime2 = startTime2 + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield2, startTime2, endTime2);

        vm.warp(endTime2);

        uint256 expectedTotalAssets = initialDeposit + bobDeposit + yield1 + yield2;
        assertEq(
            usualX.totalAssets(),
            expectedTotalAssets,
            "Total assets should include both deposits and both yield periods"
        );

        uint256 aliceAssets = usualX.convertToAssets(usualX.balanceOf(alice));
        uint256 bobAssets = usualX.convertToAssets(usualX.balanceOf(bob));

        // Alice should have more assets than Bob due to being in the vault for longer
        assertGt(aliceAssets, bobAssets, "Alice should have more assets than Bob");

        // The sum of Alice and Bob's assets should equal the total assets
        assertApproxEqAbs(
            aliceAssets + bobAssets,
            expectedTotalAssets,
            2,
            "Sum of Alice and Bob's assets should equal total assets"
        );
    }

    function testYieldWithIntermediateWithdrawal() public {
        uint256 initialDeposit = 1000e18;
        uint256 yield1 = 100e18;
        uint256 aliceWithdrawal = 300e18;
        uint256 yield2 = 50e18;
        uint256 aliceWithdrawalFee = _calculateFee(aliceWithdrawal);
        uint256 expectedTotalAssetsAlice = initialDeposit + yield1 + yield2 - aliceWithdrawalFee;

        // Alice's initial deposit
        vm.startPrank(admin);
        usualToken.mint(alice, initialDeposit);
        vm.stopPrank();

        vm.startPrank(alice);
        usualToken.approve(address(usualX), initialDeposit);
        usualX.deposit(initialDeposit, alice);
        vm.stopPrank();

        // First yield period
        vm.prank(admin);
        usualToken.mint(address(usualX), yield1);

        uint256 startTime1 = block.timestamp + 1 hours;
        uint256 endTime1 = startTime1 + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield1, startTime1, endTime1);

        vm.warp(startTime1 + 12 hours);

        // Alice withdraws midway through first yield period
        vm.prank(alice);
        usualX.withdraw(aliceWithdrawal, alice, alice);

        vm.warp(endTime1);

        // Second yield period
        vm.prank(admin);
        usualToken.mint(address(usualX), yield2);

        uint256 startTime2 = endTime1;
        uint256 endTime2 = startTime2 + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield2, startTime2, endTime2);

        vm.warp(endTime2);

        uint256 expectedTotalAssets =
            initialDeposit - aliceWithdrawal - aliceWithdrawalFee + yield1 + yield2;
        assertEq(
            usualX.totalAssets(),
            expectedTotalAssets,
            "Total assets should reflect withdrawal and both yield periods"
        );

        uint256 aliceAssets = usualX.convertToAssets(usualX.balanceOf(alice));
        assertApproxEqAbs(
            aliceAssets, expectedTotalAssets, 1, "Alice's assets should equal total assets"
        );

        // Check that Alice's total assets (including withdrawn amount) are correct
        uint256 aliceTotalAssets = aliceAssets + aliceWithdrawal;

        assertApproxEqAbs(
            aliceTotalAssets,
            expectedTotalAssetsAlice,
            1,
            "Alice's total assets should include withdrawn amount and all yield"
        );
    }

    function testComplexYieldScenario() public {
        // Initial setup
        address[] memory users = new address[](3);
        uint256 expectedTotalAssets;
        users[0] = alice;
        users[1] = bob;
        users[2] = carol;

        uint256 initialMint = 10_000e18;
        uint256 initialDeposit = 1000e18;

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(admin);
            usualToken.mint(users[i], initialMint);

            vm.startPrank(users[i]);
            usualToken.approve(address(usualX), initialMint);
            usualX.deposit(initialDeposit, users[i]);
            vm.stopPrank();
        }
        expectedTotalAssets += initialDeposit * 3;
        // First yield period
        uint256 yield1 = 300e18;
        vm.prank(admin);
        usualToken.mint(address(usualX), yield1);
        expectedTotalAssets += yield1;

        uint256 startTime1 = block.timestamp + 1 hours;
        uint256 endTime1 = startTime1 + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield1, startTime1, endTime1);

        vm.warp(startTime1 + 12 hours);

        // Mid first yield period actions
        uint256 aliceWithdraw = 200e18;
        uint256 aliceWithdrawFee = _calculateFee(aliceWithdraw);
        vm.prank(alice);
        usualX.withdraw(aliceWithdraw, alice, alice);
        expectedTotalAssets -= (aliceWithdraw + aliceWithdrawFee);

        vm.prank(bob);
        usualX.deposit(500e18, bob);
        expectedTotalAssets += 500e18;

        vm.warp(endTime1);

        // Second yield period
        uint256 yield2 = 200e18;
        vm.prank(admin);
        usualToken.mint(address(usualX), yield2);
        expectedTotalAssets += yield2;

        uint256 startTime2 = endTime1;
        uint256 endTime2 = startTime2 + 1 days;

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yield2, startTime2, endTime2);

        vm.warp(startTime2 + 12 hours);

        // Mid second yield period actions
        uint256 carolWithdraw = 500e18;
        uint256 carolWithdrawFee = _calculateFee(carolWithdraw);
        expectedTotalAssets -= (carolWithdraw + carolWithdrawFee);

        vm.prank(carol);
        usualX.withdraw(carolWithdraw, carol, carol);

        vm.prank(alice);
        usualX.deposit(300e18, alice);

        vm.warp(endTime2);
        // Final assertions
        expectedTotalAssets += (300e18);
        assertEq(
            usualX.totalAssets(), expectedTotalAssets, "Total assets should match expected value"
        );

        uint256 totalUserAssets = usualX.convertToAssets(usualX.totalSupply());
        assertApproxEqAbs(
            totalUserAssets, expectedTotalAssets, 1, "Sum of user assets should equal total assets"
        );

        // Check that users who deposited more or earlier have more assets
        assertGt(
            usualX.convertToAssets(usualX.balanceOf(bob)),
            usualX.convertToAssets(usualX.balanceOf(alice)),
            "Bob should have more assets than Alice"
        );
        assertGt(
            usualX.convertToAssets(usualX.balanceOf(bob)),
            usualX.convertToAssets(usualX.balanceOf(carol)),
            "Bob should have more assets than Carol"
        );
    }

    function testPauseUnPauseShouldFailWhenNotAuthorized() external {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualX.pause();
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualX.unpause();
    }

    function testPauseUnPauseShouldWorkWhenAuthorized() external {
        vm.prank(pauser);
        usualX.pause();
        vm.prank(admin);
        usualX.unpause();
    }

    function testBurnFromVault() public {
        vm.startPrank(admin);
        usualToken.mint(alice, 10e18);
        assertEq(usualToken.balanceOf(alice), 10e18);
        vm.stopPrank();

        vm.prank(address(usualX));
        usualToken.burnFrom(alice, 8e18);

        assertEq(usualToken.totalSupply(), 2e18);
        assertEq(usualToken.balanceOf(alice), 2e18);
    }

    function testBlacklistShouldRevertIfAddressIsZero() external {
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        usualX.blacklist(address(0));
    }

    function testBlacklistAndUnBlacklistEmitsEvents() external {
        vm.startPrank(blacklistOperator);
        vm.expectEmit();
        emit Blacklist(alice);
        usualX.blacklist(alice);

        vm.expectEmit();
        emit UnBlacklist(alice);
        usualX.unBlacklist(alice);
        vm.stopPrank();
    }

    function testOnlyBlacklistRoleCanUseBlacklist(address user) external {
        vm.assume(user != blacklistOperator);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualX.blacklist(alice);

        vm.prank(blacklistOperator);
        usualX.blacklist(alice);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualX.unBlacklist(alice);
    }

    function testNoDoubleBlacklist() external {
        vm.prank(blacklistOperator);
        usualX.blacklist(alice);

        vm.prank(blacklistOperator);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        usualX.blacklist(alice);

        assertEq(usualX.isBlacklisted(alice), true);

        vm.prank(blacklistOperator);
        usualX.unBlacklist(alice);

        vm.prank(blacklistOperator);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        usualX.unBlacklist(alice);
    }

    function testTransferFrom() public {
        uint256 amount = 100e18;
        vm.prank(admin);
        usualToken.mint(alice, amount);

        vm.prank(alice);
        usualToken.approve(address(usualX), amount);

        vm.prank(alice);
        usualX.deposit(amount, alice);

        vm.prank(alice);
        usualX.approve(bob, amount);

        vm.prank(bob);
        assertTrue(usualX.transferFrom(alice, carol, amount));

        assertEq(usualX.balanceOf(carol), amount);
        assertEq(usualX.balanceOf(alice), 0);
    }

    function testUpdateWithdrawFee() public {
        uint256 newFee = 200; // 2%
        vm.prank(withdrawFeeUpdater);
        usualX.updateWithdrawFee(newFee);

        assertEq(usualX.withdrawFeeBps(), newFee, "Withdraw fee should be updated");
    }

    function testUpdateWithdrawFeeEmitsEvent() public {
        uint256 newFee = 200; // 2%
        vm.prank(withdrawFeeUpdater);
        vm.expectEmit(true, false, false, true);
        emit WithdrawFeeUpdated(newFee);
        usualX.updateWithdrawFee(newFee);
    }

    function testUpdateWithdrawFeeFailsNotAdmin() public {
        uint256 newFee = 200; // 2%
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualX.updateWithdrawFee(newFee);
    }

    function testUpdateWithdrawFeeFailsExceedsMax() public {
        uint256 newFee = MAX_25_PERCENT_WITHDRAW_FEE + 1;
        vm.prank(withdrawFeeUpdater);
        vm.expectRevert(abi.encodeWithSelector(AmountTooBig.selector));
        usualX.updateWithdrawFee(newFee);
    }

    function testUpdateWithdrawFeeAffectsWithdrawals() public {
        uint256 initialDeposit = 1000e18;
        uint256 withdrawAmount = 100e18;
        uint256 newFee = 200; // 2%

        // Setup
        vm.prank(admin);
        usualToken.mint(alice, initialDeposit);

        vm.startPrank(alice);
        usualToken.approve(address(usualX), initialDeposit);
        usualX.deposit(initialDeposit, alice);
        vm.stopPrank();

        // Update fee
        vm.prank(withdrawFeeUpdater);
        usualX.updateWithdrawFee(newFee);

        // Calculate expected fee before withdrawal
        uint256 expectedFee =
            Math.mulDiv(withdrawAmount, newFee, BASIS_POINT_BASE - newFee, Math.Rounding.Ceil);
        uint256 expectedSharesBurned = usualX.convertToShares(withdrawAmount + expectedFee);

        // Withdraw
        vm.prank(alice);
        uint256 sharesBurned = usualX.withdraw(withdrawAmount, alice, alice);

        assertEq(sharesBurned, expectedSharesBurned, "Incorrect shares burned after fee update");
    }

    function testUpdateWithdrawFeeZero() public {
        uint256 newFee = 0;
        vm.prank(withdrawFeeUpdater);
        usualX.updateWithdrawFee(newFee);

        assertEq(usualX.withdrawFeeBps(), newFee, "Withdraw fee should be updated to zero");
    }

    function testStartYieldDistributionZeroAmount() public {
        vm.prank(distributionModuleAddress);
        vm.expectRevert(ZeroYieldAmount.selector);
        usualX.startYieldDistribution(0, block.timestamp + 1 hours, block.timestamp + 2 hours);
    }

    function testStartYieldDistribution_RevertsIfNotDistributionModule() public {
        vm.expectRevert(NotAuthorized.selector);
        usualX.startYieldDistribution(100e18, block.timestamp + 1 hours, block.timestamp + 2 hours);
    }

    function testStartYieldDistributionPastStartTime() public {
        vm.prank(distributionModuleAddress);
        vm.expectRevert(StartTimeNotInFuture.selector);
        usualX.startYieldDistribution(100e18, block.timestamp - 1, block.timestamp + 1 hours);
    }

    function testStartYieldDistributionEndTimeBeforeStartTime() public {
        vm.prank(distributionModuleAddress);
        vm.expectRevert(EndTimeNotAfterStartTime.selector);
        usualX.startYieldDistribution(100e18, block.timestamp + 2 hours, block.timestamp + 1 hours);
    }

    function testStartYieldDistributionStartTimeBeforePeriodFinish() public {
        testStartYieldDistributionSuccess();

        vm.prank(distributionModuleAddress);
        vm.expectRevert(StartTimeBeforePeriodFinish.selector);
        usualX.startYieldDistribution(100e18, block.timestamp, block.timestamp + 2 hours);
    }

    function testStartYieldDistributionInsufficientAssets() public {
        uint256 yieldAmount = 100e18;
        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 1 days;

        // Ensure the contract doesn't have enough assets
        assertLt(
            usualToken.balanceOf(address(usualX)),
            yieldAmount,
            "Test setup: contract should not have enough assets"
        );

        vm.prank(distributionModuleAddress);
        vm.expectRevert(InsufficientAssetsForYield.selector);
        usualX.startYieldDistribution(yieldAmount, startTime, endTime);
    }

    function testStartYieldDistributionSuccess() public {
        uint256 yieldAmount = 100e18;
        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 1 days;

        // Ensure the contract has enough assets
        vm.prank(admin);
        usualToken.mint(address(usualX), yieldAmount);

        uint256 initialTotalDeposits = getTotalDeposits();

        vm.prank(distributionModuleAddress);
        usualX.startYieldDistribution(yieldAmount, startTime, endTime);

        // Verify that the yield distribution started successfully
        assertTrue(getIsActive(), "Yield distribution should be active");
        assertEq(getPeriodStart(), startTime, "Start time should be set correctly");
        assertEq(getPeriodFinish(), endTime, "End time should be set correctly");
        assertEq(getLastUpdateTime(), startTime, "Last update time should be set to start time");
        assertTrue(usualX.getYieldRate() > 0, "Yield rate should be set");

        // Verify that totalDeposits hasn't changed
        assertEq(getTotalDeposits(), initialTotalDeposits, "Total deposits should not change");

        // Calculate and verify the yield rate
        uint256 expectedYieldRate = (yieldAmount * YIELD_PRECISION) / (endTime - startTime);
        assertEq(
            usualX.getYieldRate(), expectedYieldRate, "Yield rate should be calculated correctly"
        );
    }

    function testConstructorDoesNotRevert() public {
        UsualX newUsualX = new UsualX();
        assertTrue(address(newUsualX) != address(0), "Constructor should not revert");
    }
}
