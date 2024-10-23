// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SetupTest} from "../setup.t.sol";

import {DistributionModule} from "src/distribution/DistributionModule.sol";

import {USUAL_DISTRIBUTION_CHALLENGE_PERIOD, ONE_YEAR, SCALAR_ONE} from "src/constants.sol";

contract DistributionModuleIntegrationTest is SetupTest {
    uint256 constant INITIAL_USD0PP_SUPPLY = 57_151.57026e18;
    uint256 constant INITIAL_RATE0 = 545;

    struct DailyData {
        uint256 day;
        uint256 totalSupply;
        uint256 gamma;
        uint256 ratet;
        uint256 p90Rate;
        uint256 rate0;
        uint256 expectedUsualDist;
    }

    DailyData[] public realData;

    bytes32 constant FIRST_MERKLE_ROOT =
        bytes32(0xb27bba74a96ad64a5af960ef7109122a74d29e60b33b803a95a8169452bab97c);

    bytes32 constant SECOND_MERKLE_ROOT =
        bytes32(0x42c0f6fb540d80944343aa60ad559f96980e8217b5893243536bfe7acc6a9325);

    uint256 public aliceAmountInFirstMerkleTree = 10e18;
    uint256 public aliceAmountInSecondMerkleTree = 20e18;

    uint256 public bobAllocationInUsualSP = 10e18;

    uint256 public carolDepositInUsualX = 30e18;

    function _aliceProofForFirstMerkleTree() internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(0xd264c5e17b739c107b433ce4e73900487afb6cc6cbeb9f1651a640e411a591db);
        proof[1] = bytes32(0xdb61b8f77a945a119bb321e1044d8808ab64c81210661e930d0bf8363218d3ba);
        return proof;
    }

    function _aliceProofForSecondMerkleTree() internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(0xd704cf18239df2db7bb4fbdbf9a5ba2d210366214444bf3a1d11b8be63f5e62d);
        proof[1] = bytes32(0x7a01ed93feeb76b2608cfad220ccddf2470e723027d73ed4ee49208a6fbe91de);
        return proof;
    }

    /*//////////////////////////////////////////////////////////////
                            1. SETUP & HELPERS
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();

        uint256 amount = INITIAL_USD0PP_SUPPLY;
        vm.prank(address(daoCollateral));
        deal(address(stbcToken), alice, amount);
        deal(address(stbcToken), bob, amount);
        deal(address(stbcToken), carol, amount);

        vm.startPrank(address(alice));
        stbcToken.approve(address(usd0PP), amount);
        usd0PP.mint(amount);
        vm.stopPrank();

        vm.startPrank(address(bob));
        stbcToken.approve(address(usd0PP), amount);
        usd0PP.mint(amount);
        vm.stopPrank();

        vm.startPrank(address(carol));
        stbcToken.approve(address(usd0PP), amount);
        usd0PP.mint(amount);
        vm.stopPrank();

        // Stake USUALS in UsualSP
        vm.prank(usualSPOperator);
        usualSP.stakeUsualS();

        // After minting, we need to reinitialize the DistributionModule
        // This is because the initial supply is stored during initialization
        _resetInitializerImplementation(address(distributionModule));
        vm.prank(admin);
        distributionModule.initialize(registryContract, INITIAL_RATE0);

        setUpTestData();
        setupVestingInUsualSPForBob();
        setupUsualXForCarol();
    }

    function setUpTestData() internal {
        realData.push(DailyData(1, 57_151.57026e18, 10_000, 545, 551, 545, 391.4491e18));
        realData.push(DailyData(2, 38_360_239.9e18, 10_000, 546, 551, 546, 392.1674e18));
        realData.push(DailyData(3, 47_942_400.76e18, 10_000, 548, 551, 547, 393.6039e18));
        realData.push(DailyData(4, 54_385_577.55e18, 10_000, 547, 5501, 547, 392.8856e18));
        realData.push(DailyData(5, 59_627_462.99e18, 10_000, 547, 5501, 547, 392.8856e18));
        realData.push(DailyData(6, 60_849_671.14e18, 10_000, 547, 5501, 547, 392.8856e18));
        realData.push(DailyData(7, 68_263_281.09e18, 10_000, 548, 5501, 548, 393.6039e18));
        realData.push(DailyData(8, 69_908_471.89e18, 10_000, 548, 550, 548, 393.6039e18));
        realData.push(DailyData(9, 72_451_402.37e18, 10_000, 547, 550, 548, 392.8856e18));
        realData.push(DailyData(10, 73_385_798.95e18, 10_000, 548, 550, 548, 393.6039e18));
        realData.push(DailyData(11, 75_588_247.22e18, 10_000, 548, 550, 548, 393.6039e18));
    }

    function setupVestingInUsualSPForBob() internal {
        address[] memory recipient = new address[](1);
        recipient[0] = bob;
        uint256[] memory allocation = new uint256[](1);
        allocation[0] = bobAllocationInUsualSP;
        uint256[] memory cliffDurations = new uint256[](1);
        cliffDurations[0] = ONE_YEAR;

        vm.prank(usualSPOperator);
        usualSP.allocate(recipient, allocation, cliffDurations);
    }

    function setupUsualXForCarol() internal {
        vm.prank(admin);
        usualToken.mint(carol, carolDepositInUsualX);

        vm.startPrank(carol);
        usualToken.approve(address(usualX), carolDepositInUsualX);
        usualX.deposit(carolDepositInUsualX, carol);
        vm.stopPrank();
    }

    function testDistributionAndGammaCalculation() public {
        uint256 initialGamma = distributionModule.calculateGamma();
        assertEq(initialGamma, SCALAR_ONE, "Initial gamma should be SCALAR_ONE");

        for (uint256 i = 0; i < realData.length; i++) {
            // Simulate passage of time
            skip(1 days);

            // Perform on-chain distribution
            vm.prank(distributionOperator);
            distributionModule.distributeUsualToBuckets(realData[i].ratet, realData[i].p90Rate);

            // Check gamma after on-chain distribution
            uint256 gammaAfterOnChainDistribution = distributionModule.calculateGamma();
            assertEq(
                gammaAfterOnChainDistribution,
                SCALAR_ONE,
                "Gamma should reset to SCALAR_ONE after on-chain distribution"
            );

            // Simulate passage of time without distribution
            skip(2 days);

            // Check gamma after time passage
            uint256 gammaAfterTimePassed = distributionModule.calculateGamma();
            assertEq(
                gammaAfterTimePassed,
                SCALAR_ONE / 2,
                "Gamma should decrease after time passes without distribution"
            );
        }
    }

    function test_singleDayDistribution() external {
        DailyData memory firstDayData = realData[0];
        uint256 carolUsualXInitialBalance = usualX.convertToAssets(usualX.balanceOf(carol));

        skip(1 days);
        vm.prank(distributionOperator);
        distributionModule.distributeUsualToBuckets(firstDayData.ratet, firstDayData.p90Rate);

        uint256 momentOfDistribution = block.timestamp;

        // Check if Alice can claim the off-chain reward after it was in queue
        vm.prank(distributionOperator);
        distributionModule.queueOffChainUsualDistribution(FIRST_MERKLE_ROOT);

        skip(USUAL_DISTRIBUTION_CHALLENGE_PERIOD);
        distributionModule.approveUnchallengedOffChainDistribution();

        uint256 aliceUsualBalanceBefore = usualToken.balanceOf(alice);

        vm.prank(alice);
        distributionModule.claimOffChainDistribution(
            alice, aliceAmountInFirstMerkleTree, _aliceProofForFirstMerkleTree()
        );

        assertEq(
            usualToken.balanceOf(alice), aliceUsualBalanceBefore + aliceAmountInFirstMerkleTree
        );

        vm.warp(momentOfDistribution);

        // Check if Bob can claim the rewards from UsualSP
        skip(ONE_YEAR);

        uint256 bobBalanceBefore = usualToken.balanceOf(bob);
        uint256 expectedBobReward = 3_262_075_928_082;

        vm.prank(bob);
        usualSP.claimReward();

        assertEq(usualToken.balanceOf(bob), bobBalanceBefore + expectedBobReward);

        vm.warp(momentOfDistribution);

        // Check if Carol assets in UsualX increased
        uint256 carolUsualXBalanceAfterDistribution =
            usualX.convertToAssets(usualX.balanceOf(carol));

        assertEq(carolUsualXInitialBalance, carolUsualXBalanceAfterDistribution);

        skip(1 days);

        uint256 carolUsualXBalanceAfter1Day = usualX.convertToAssets(usualX.balanceOf(carol));
        assertGt(carolUsualXBalanceAfter1Day, carolUsualXInitialBalance);
    }
}
