// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SetupTest} from "test/setup.t.sol";
import {console} from "forge-std/console.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import {
    USUALS_TOTAL_SUPPLY,
    ONE_YEAR,
    ONE_MONTH,
    VESTING_DURATION_THREE_YEARS,
    PAUSING_CONTRACTS_ROLE
} from "src/constants.sol";
import {
    NullContract,
    InvalidInputArraysLength,
    InvalidInput,
    StartTimeInPast,
    CliffBiggerThanDuration,
    NotAuthorized,
    AmountIsZero,
    NotClaimableYet,
    AlreadyClaimed,
    InsufficientUsualSAllocation,
    InsufficientUsualSLiquidAllocation,
    EndTimeBeforeStartTime,
    StartTimeInPast,
    AlreadyStarted,
    CannotReduceAllocation
} from "src/errors.sol";
import {UsualSP} from "src/token/UsualSP.sol";
import {UsualS} from "src/token/UsualS.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

import {Pausable} from "openzeppelin-contracts/utils/Pausable.sol";

// @title: UsualSP test contract
// @notice: Contract to test UsualSP token implementation

contract UsualSPTest is SetupTest {
    using Math for uint256;

    event ClaimedOriginalAllocation(address indexed account, uint256 amount);
    event NewAllocation(address[] recipients, uint256[] allocations, uint256[] cliffDurations);
    event RewardClaimed(address indexed user, uint256 reward);
    event RewardPeriodStarted(uint256 rewardAmount, uint256 startTime, uint256 endTime);
    event RewardRateChanged(uint256 rewardRate);

    function setUp() public virtual override {
        super.setUp();
        vm.prank(usualSPOperator);
        usualSP.stakeUsualS();
        vm.assertEq(usualS.balanceOf(address(usualSP)), USUALS_TOTAL_SUPPLY);
    }

    /*//////////////////////////////////////////////////////////////
                            0. Setup functions
    //////////////////////////////////////////////////////////////*/

    function setupVesting(
        address[] memory recipient,
        uint256[] memory allocation,
        uint256[] memory cliffDurations
    ) internal {
        vm.prank(usualSPOperator);
        usualSP.allocate(recipient, allocation, cliffDurations);
    }

    function setupVestingWithAliceAndBob(
        uint256 amountAlice,
        uint256 amountBob,
        uint256 cliffDurationAlice,
        uint256 cliffDurationBob
    ) internal {
        address[] memory recipient = new address[](2);
        recipient[0] = alice;
        recipient[1] = bob;
        uint256[] memory allocation = new uint256[](2);
        allocation[0] = amountAlice;
        allocation[1] = amountBob;
        uint256[] memory cliffDurations = new uint256[](2);
        cliffDurations[0] = cliffDurationAlice;
        cliffDurations[1] = cliffDurationBob;

        setupVesting(recipient, allocation, cliffDurations);
    }

    function setupVestingWithOneYearCliff(uint256 amount) internal {
        setupVestingWithAliceAndBob(amount, amount, ONE_YEAR, ONE_YEAR);
    }

    function setupStartOneDayRewardDistribution(uint256 amount) internal {
        deal(address(usualToken), address(distributionModule), amount);
        vm.startPrank(address(distributionModule));
        usualToken.approve(address(usualSP), amount);
        usualSP.startRewardDistribution(amount, block.timestamp, block.timestamp + 1 days); // 1 day
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            1. Initialization
    //////////////////////////////////////////////////////////////*/

    // 1.1 Testing revert properties //

    function testInitializeShouldFailWithNullAddress() public {
        _resetInitializerImplementation(address(usualSP));
        vm.expectRevert(abi.encodeWithSelector(NullContract.selector));
        usualSP.initialize(address(0), 0, 0);
    }

    function testInitializeShouldFailIfStartTimeLtTimestamp() public {
        _resetInitializerImplementation(address(usualSP));
        vm.expectRevert(abi.encodeWithSelector(StartTimeInPast.selector));
        usualSP.initialize(address(registryContract), 0, 0);
    }

    function testInitializeShouldFailIfDurationIsZero() public {
        _resetInitializerImplementation(address(usualSP));
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        usualSP.initialize(address(registryContract), block.timestamp + 100, 0);
    }

    // 1.2 Testing basic flows //

    function testInitialize() public {
        _resetInitializerImplementation(address(usualSP));
        usualSP.initialize(
            address(registryContract), block.timestamp + 100, VESTING_DURATION_THREE_YEARS
        );
    }

    function testConstructor() public {
        UsualSP usualSP = new UsualSP();
        assertEq(usualSP.paused(), false);
    }

    /*//////////////////////////////////////////////////////////////
                        2. ClaimOriginalAllocation
    //////////////////////////////////////////////////////////////*/

    // 2.1 Testing revert properties //

    function testClaimRevertIfNotAuthorized() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualSP.claimOriginalAllocation();
    }

    function testClaimRevertIfNotClaimableYet() public {
        setupVestingWithOneYearCliff(100);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotClaimableYet.selector));
        usualSP.claimOriginalAllocation();
    }

    function testClaimRevertIfPaused() public {
        setupVestingWithOneYearCliff(100);

        vm.startPrank(pauser);
        usualSP.pause();

        skip(VESTING_DURATION_THREE_YEARS);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        usualSP.claimOriginalAllocation();
    }

    function testClaimRevertIfAlreadyClaimed() public {
        setupVestingWithOneYearCliff(100);

        skip(VESTING_DURATION_THREE_YEARS);

        vm.startPrank(alice);
        usualSP.claimOriginalAllocation();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(AlreadyClaimed.selector));
        usualSP.claimOriginalAllocation();
    }

    // 2.2 Testing basic flows //

    function testClaimAfterVesting(uint256 amount) public {
        amount = bound(amount, 1e18, USUALS_TOTAL_SUPPLY / 2);
        setupVestingWithOneYearCliff(amount);

        skip(VESTING_DURATION_THREE_YEARS);

        vm.startPrank(alice);
        usualSP.claimOriginalAllocation();

        assertEq(usualS.balanceOf(alice), amount);
    }

    function testClaimForEachMonthWithOneYearCliff(uint256 amount) public {
        amount = bound(amount, 1e18, USUALS_TOTAL_SUPPLY / 2);
        uint256 oneThird = amount / 3;
        uint256 twoThird = oneThird * 2;

        setupVestingWithOneYearCliff(amount);
        skip(ONE_YEAR);

        for (uint256 i = 0; i < 24; i++) {
            skip(ONE_MONTH);
            vm.prank(alice);
            usualSP.claimOriginalAllocation();
            console.log("balance of alice", usualS.balanceOf(alice));
            assertApproxEqAbs(usualS.balanceOf(alice), oneThird + twoThird.mulDiv(i + 1, 24), 1e2);
        }

        assertEq(usualS.balanceOf(alice), amount);
    }

    function testClaimForEachMonthWithCustomCliff(uint256 amount, uint256 cliffDuration) public {
        amount = bound(amount, 1e18, USUALS_TOTAL_SUPPLY / 2);
        cliffDuration = bound(cliffDuration, 0, VESTING_DURATION_THREE_YEARS);

        address[] memory recipient = new address[](1);
        recipient[0] = alice;
        uint256[] memory allocation = new uint256[](1);
        allocation[0] = amount;
        uint256[] memory cliffDurations = new uint256[](1);
        cliffDurations[0] = cliffDuration;

        uint256 initialTimestamp = block.timestamp;
        uint256 numberOfMonthInCliff = cliffDuration / ONE_MONTH;
        uint256 claimableAmountAfterCliff = numberOfMonthInCliff * (amount / 36);
        setupVesting(recipient, allocation, cliffDurations);

        skip(cliffDuration);

        for (uint256 i = 0; i < 36; i++) {
            skip(ONE_MONTH);
            if (block.timestamp >= initialTimestamp + VESTING_DURATION_THREE_YEARS) {
                vm.prank(alice);
                usualSP.claimOriginalAllocation();
                break;
            }
            vm.prank(alice);
            usualSP.claimOriginalAllocation();
            assertApproxEqAbs(
                usualS.balanceOf(alice), claimableAmountAfterCliff + amount.mulDiv(i + 1, 36), 1e2
            );
        }

        assertEq(usualS.balanceOf(alice), amount);
    }

    function testClaimForDifferentAmountAndCliff(uint256 amount, uint256 cliffDuration) public {
        amount = bound(amount, 3e18, USUALS_TOTAL_SUPPLY / 2);
        cliffDuration = bound(cliffDuration, 0, VESTING_DURATION_THREE_YEARS - (5 * ONE_MONTH));

        address[] memory recipient = new address[](3);
        recipient[0] = alice;
        recipient[1] = bob;
        recipient[2] = carol;
        uint256[] memory allocation = new uint256[](3);
        allocation[0] = amount / 2;
        allocation[1] = allocation[0] / 2;
        allocation[2] = amount - allocation[0] - allocation[1];
        uint256[] memory cliffDurations = new uint256[](3);
        cliffDurations[0] = 2 * ONE_MONTH;
        cliffDurations[1] = 3 * ONE_MONTH;
        cliffDurations[2] = cliffDuration;

        uint256 initialTimestamp = block.timestamp;
        uint256 bobEndCliff = initialTimestamp + cliffDurations[1];
        uint256 carolEndCliff = initialTimestamp + cliffDurations[2];
        uint256 numberOfMonthInCliff = cliffDuration / ONE_MONTH;
        uint256 aliceAmountPerMonth = allocation[0] / 36;
        uint256 bobAmountPerMonth = allocation[1] / 36;
        uint256 carolAmountPerMonth = allocation[2] / 36;
        uint256 claimableAmountAfterCliffForAlice = 2 * aliceAmountPerMonth;
        uint256 claimableAmountAfterCliffForBob = 3 * bobAmountPerMonth;
        setupVesting(recipient, allocation, cliffDurations);
        assertEq(usualS.balanceOf(alice), 0);
        assertEq(usualS.balanceOf(bob), 0);
        assertEq(usualS.balanceOf(carol), 0);
        // skip two months
        skip(cliffDurations[0]);
        // alice can claim
        for (uint256 i = 0; i < 36; i++) {
            console.log("i", i);

            if (block.timestamp >= initialTimestamp + VESTING_DURATION_THREE_YEARS) {
                vm.prank(alice);
                usualSP.claimOriginalAllocation();
                vm.prank(bob);
                usualSP.claimOriginalAllocation();
                vm.prank(carol);
                usualSP.claimOriginalAllocation();
                break;
            }
            vm.prank(alice);
            usualSP.claimOriginalAllocation();
            assertApproxEqAbs(
                usualS.balanceOf(alice),
                claimableAmountAfterCliffForAlice + aliceAmountPerMonth * i,
                1e2
            );

            if (block.timestamp >= bobEndCliff) {
                vm.prank(bob);
                usualSP.claimOriginalAllocation();
                assertApproxEqAbs(
                    usualS.balanceOf(bob),
                    claimableAmountAfterCliffForBob + bobAmountPerMonth * (i - 1),
                    1e2
                );
            }
            if (block.timestamp >= carolEndCliff) {
                uint256 monthSinceCarolEndCliff =
                    (block.timestamp - initialTimestamp - cliffDuration) / ONE_MONTH;
                vm.prank(carol);
                usualSP.claimOriginalAllocation();
                assertApproxEqAbs(
                    usualS.balanceOf(carol),
                    carolAmountPerMonth * (numberOfMonthInCliff + monthSinceCarolEndCliff),
                    1e2
                );
            }

            skip(ONE_MONTH);
        }

        assertEq(usualS.balanceOf(alice), allocation[0]);
        assertEq(usualS.balanceOf(bob), allocation[1]);
        assertEq(usualS.balanceOf(carol), allocation[2]);
    }

    // unit test with Alice with 6 months cliff and 3 years vesting duration
    function testClaimWithSpecificCliff(uint256 amount) public {
        amount = bound(amount, 1e18, USUALS_TOTAL_SUPPLY / 2);
        address[] memory recipient = new address[](1);
        recipient[0] = alice;
        uint256[] memory allocation = new uint256[](1);
        allocation[0] = amount;
        uint256[] memory cliffDurations = new uint256[](1);
        cliffDurations[0] = ONE_YEAR / 2;

        setupVesting(recipient, allocation, cliffDurations);
    }

    function testClaimEmitCorrectEvent() public {
        setupVestingWithOneYearCliff(100);

        skip(VESTING_DURATION_THREE_YEARS);

        vm.startPrank(alice);
        vm.expectEmit();
        emit ClaimedOriginalAllocation(alice, 100);
        usualSP.claimOriginalAllocation();
    }

    /*//////////////////////////////////////////////////////////////
                            3. Stake
    //////////////////////////////////////////////////////////////*/

    // 3.1 Testing revert properties //

    function testStakeRevertIfAmountIsZero() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        usualSP.stake(0);
    }

    function testStakeRevertIfPaused() public {
        vm.startPrank(pauser);
        usualSP.pause();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        usualSP.stake(100);
    }

    // 3.2 Testing basic flows //

    function testStakeUsualS(uint256 amount) public {
        amount = bound(amount, 1e18, USUALS_TOTAL_SUPPLY / 2);
        deal(address(usualS), alice, amount);
        vm.startPrank(alice);
        usualS.approve(address(usualSP), amount);
        usualSP.stake(amount);
        assertEq(usualSP.balanceOf(alice), amount);
        assertEq(usualS.balanceOf(alice), 0);
    }

    /*//////////////////////////////////////////////////////////////
                         4. Stake with Permit
    //////////////////////////////////////////////////////////////*/

    // 4.1 Testing revert properties //

    function testStakeWithPermitRevertIfPermitIsInvalid() public {
        uint256 deadline = block.timestamp + 100;
        uint256 amount = 100e18;

        deal(address(usualS), alice, amount);

        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(usualS), alice, alicePrivKey, address(usualSP), amount, deadline
        );
        vm.startPrank(alice);
        // bad v
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usualSP), 0, amount
            )
        );
        usualSP.stakeWithPermit(amount, deadline, 0, r, s);

        // bad r
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usualSP), 0, amount
            )
        );
        usualSP.stakeWithPermit(amount, deadline, v, bytes32(0), s);

        // bad s
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usualSP), 0, amount
            )
        );
        usualSP.stakeWithPermit(amount, deadline, v, r, bytes32(0));

        // bad deadline
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(usualSP), 0, amount
            )
        );
        usualSP.stakeWithPermit(amount, deadline + 1, v, r, s);
    }

    // 4.2 Testing basic flows //

    function testStakeWithPermit(uint256 amount) public {
        amount = bound(amount, 1e18, USUALS_TOTAL_SUPPLY);
        deal(address(usualS), alice, amount);
        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(usualS), alice, alicePrivKey, address(usualSP), amount, deadline
        );
        vm.prank(alice);
        usualSP.stakeWithPermit(amount, deadline, v, r, s);

        assertEq(usualSP.balanceOf(alice), amount);
        assertEq(usualS.balanceOf(alice), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            5. Unstake
    //////////////////////////////////////////////////////////////*/

    // 5.1 Testing revert properties //

    function testUnstakeRevertIfAmountIsZero() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        usualSP.unstake(0);
    }

    function testUnstakeRevertIfPaused() public {
        vm.startPrank(pauser);
        usualSP.pause();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        usualSP.unstake(100);
    }

    function testUnstakeRevertIfNotEnoughBalance() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(InsufficientUsualSLiquidAllocation.selector));
        usualSP.unstake(100);
    }

    // 5.2 Testing basic flows //

    function testUnstakeAllocation(uint256 amount) public {
        amount = bound(amount, 1e18, USUALS_TOTAL_SUPPLY / 2);
        uint256 rewardAmount = 100e18;
        testStakeUsualS(amount);

        deal(address(usualToken), address(distributionModule), rewardAmount);

        vm.startPrank(address(distributionModule));
        usualToken.approve(address(usualSP), rewardAmount);
        usualSP.startRewardDistribution(rewardAmount, block.timestamp, block.timestamp + 1 days);
        vm.stopPrank();

        vm.startPrank(alice);
        usualSP.unstake(amount);
        assertEq(usualSP.balanceOf(alice), 0);
        assertEq(usualS.balanceOf(alice), amount);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            6. ClaimReward
    //////////////////////////////////////////////////////////////*/

    // 6.1 Testing revert properties //

    function testClaimRewardRevertIfPaused() public {
        vm.startPrank(pauser);
        usualSP.pause();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        usualSP.claimReward();
    }

    function testClaimRewardRevertIfNotClaimableYet() public {
        setupStartOneDayRewardDistribution(1e18);
        setupVestingWithOneYearCliff(3_600_000e18); // 1% of USUALS_TOTAL_SUPPLY
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotClaimableYet.selector));
        usualSP.claimReward();
    }

    // 6.2 Testing basic flows //

    function testClaimRewardWith1PercentReward(uint256 amount) public {
        skip(ONE_MONTH);
        amount = bound(amount, 1e18, USUALS_TOTAL_SUPPLY);
        setupStartOneDayRewardDistribution(amount);
        setupVestingWithOneYearCliff(3_600_000e18); // 1% of USUALS_TOTAL_SUPPLY
        assertEq(usualSP.balanceOf(alice), 3_600_000e18);

        skip(1 days);

        vm.startPrank(alice);
        usualSP.claimReward();
        uint256 onePercentOfReward = amount.mulDiv(1, 100);
        assertApproxEqAbs(usualToken.balanceOf(alice), onePercentOfReward, 1e3); // 1e3 for precision loss
    }

    function testClaimRewardAfterSomeoneElseClaimed(uint256 amount) public {
        skip(ONE_MONTH);
        amount = bound(amount, 1e18, USUALS_TOTAL_SUPPLY);
        setupStartOneDayRewardDistribution(amount);
        setupVestingWithOneYearCliff(3_600_000e18); // 1% of USUALS_TOTAL_SUPPLY

        skip(1 days);

        vm.startPrank(alice);
        usualSP.claimReward();
        uint256 onePercentOfReward = amount.mulDiv(1, 100);
        assertApproxEqAbs(usualToken.balanceOf(alice), onePercentOfReward, 1e6); // 1e6 for precision loss
        vm.stopPrank();

        vm.startPrank(bob);
        usualSP.claimReward();
        assertApproxEqAbs(usualToken.balanceOf(bob), onePercentOfReward, 1e6); // 1e6 for precision loss
    }

    function testClaimRewardAfterMultipleRewardPeriods(uint256 amount) public {
        skip(ONE_MONTH);
        amount = bound(amount, 1e18, USUALS_TOTAL_SUPPLY);

        uint256 aliceBalance = 3_600_000e18; // 1% of USUALS_TOTAL_SUPPLY
        setupVestingWithOneYearCliff(aliceBalance);
        assertEq(usualSP.balanceOf(alice), aliceBalance);

        for (uint256 i = 0; i < 7; i++) {
            setupStartOneDayRewardDistribution(amount);
            skip(1 days);
        }

        vm.prank(alice);
        usualSP.claimReward();
        uint256 expectedReward = (amount * 7) / 100; // 1% of total rewards (7 * amount)
        assertApproxEqAbs(usualToken.balanceOf(alice), expectedReward, 1e6);
    }

    function testClaimableAmountIncreasesWithTime() public {
        skip(ONE_MONTH);
        uint256 rewardAmount = 24e18; // 24 tokens for 24 hours
        uint256 aliceAllocation = USUALS_TOTAL_SUPPLY; // 100% of allocation

        setupStartOneDayRewardDistribution(rewardAmount);
        setupVestingWithOneYearCliff(aliceAllocation);
        assertEq(usualSP.balanceOf(alice), aliceAllocation);

        uint256 expectedClaimablePerHour = rewardAmount / 24; // Reward per hour

        vm.startPrank(alice);
        for (uint256 hour = 1; hour <= 24; hour++) {
            skip(1 hours);
            uint256 expectedClaimable = (expectedClaimablePerHour * hour);
            usualSP.claimReward();
            assertApproxEqAbs(usualToken.balanceOf(alice), expectedClaimable, 1e6);
        }
        vm.stopPrank();
    }

    function testClaimRewardEmitEvent() public {
        skip(ONE_MONTH);
        setupVestingWithOneYearCliff(USUALS_TOTAL_SUPPLY / 2);
        setupStartOneDayRewardDistribution(2e18);
        skip(1 days);

        vm.startPrank(alice);
        uint256 reward = usualSP.claimReward();
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectEmit();
        emit RewardClaimed(bob, reward);
        usualSP.claimReward();
    }

    /*//////////////////////////////////////////////////////////////
                            7. Pause and Unpause
    //////////////////////////////////////////////////////////////*/

    // 7.1 Testing revert properties //

    function testPauseUnpauseRevertsIfNotAuthorized() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualSP.pause();
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualSP.unpause();
    }

    // 7.2 Testing basic flows //

    function testPauseAndUnpause() public {
        vm.prank(pauser);
        usualSP.pause();
        vm.assertEq(usualSP.paused(), true);
        vm.prank(admin);
        usualSP.unpause();
        vm.assertEq(usualSP.paused(), false);
    }

    /*//////////////////////////////////////////////////////////////
                            8. Allocate
    //////////////////////////////////////////////////////////////*/

    // 8.1 Testing revert properties //

    function testAllocateRevertIfNotAuthorized() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualSP.allocate(new address[](0), new uint256[](0), new uint256[](0));
    }

    function testAllocateRevertIfCliffDurationIsGreaterThanVestingDuration() public {
        address[] memory recipient = new address[](1);
        recipient[0] = alice;

        uint256[] memory allocation = new uint256[](1);
        allocation[0] = 100;

        uint256[] memory cliffDurations = new uint256[](1);
        cliffDurations[0] = usualSP.getDuration() + 1;

        vm.startPrank(usualSPOperator);
        vm.expectRevert(abi.encodeWithSelector(CliffBiggerThanDuration.selector));
        usualSP.allocate(recipient, allocation, cliffDurations);
    }

    function testAllocateRevertIfLengthsAreDifferent() public {
        vm.startPrank(usualSPOperator);
        vm.expectRevert(abi.encodeWithSelector(InvalidInputArraysLength.selector));
        usualSP.allocate(new address[](1), new uint256[](2), new uint256[](2));
    }

    function testAllocateRevertIfZeroAddress() public {
        vm.startPrank(usualSPOperator);
        vm.expectRevert(abi.encodeWithSelector(InvalidInput.selector));
        usualSP.allocate(new address[](1), new uint256[](1), new uint256[](1));
    }

    // 8.2 Testing basic flows //

    function testAllocateEmitEvent() public {
        address[] memory recipient = new address[](2);
        recipient[0] = alice;
        recipient[1] = bob;

        uint256[] memory allocation = new uint256[](2);
        allocation[0] = 100;
        allocation[1] = 100;

        uint256[] memory cliffDurations = new uint256[](2);
        cliffDurations[0] = ONE_YEAR;
        cliffDurations[1] = ONE_YEAR;

        vm.startPrank(usualSPOperator);
        vm.expectEmit();
        emit NewAllocation(recipient, allocation, cliffDurations);
        usualSP.allocate(recipient, allocation, cliffDurations);

        assertEq(usualSP.balanceOf(alice), 100);
        assertEq(usualSP.balanceOf(bob), 100);
    }

    /*//////////////////////////////////////////////////////////////
                          9. Remove Original Allocation
    //////////////////////////////////////////////////////////////*/

    // 9.1 Testing revert properties //

    function testRemoveAllocationRevertIfNotAuthorized() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualSP.removeOriginalAllocation(new address[](2));
    }

    function testRemoveAllocationRevertIfRecipientNotFound() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(InvalidInputArraysLength.selector));
        usualSP.removeOriginalAllocation(new address[](0));
    }

    // 9.2 Testing basic flows //

    function testRemoveAllocation() public {
        setupVestingWithOneYearCliff(100);

        address[] memory recipientToRemove = new address[](1);
        recipientToRemove[0] = alice;

        vm.startPrank(usualSPOperator);
        usualSP.removeOriginalAllocation(recipientToRemove);

        assertEq(usualSP.balanceOf(alice), 0);
        assertEq(usualSP.balanceOf(bob), 100);
    }

    /*//////////////////////////////////////////////////////////////
                            10. Start Reward Distribution
    //////////////////////////////////////////////////////////////*/

    // 10.1 Testing revert properties //

    function testStartRewardDistributionRevertIfNotAuthorized() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualSP.startRewardDistribution(100, block.timestamp, block.timestamp + 1 days);
    }

    function testStartRewardDistributionRevertIfAmountIsZero() public {
        vm.prank(address(distributionModule));
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        usualSP.startRewardDistribution(0, block.timestamp, block.timestamp + 1 days);
    }

    function testStartRewardDistributionRevertIfStartTimeIsZero() public {
        vm.prank(address(distributionModule));
        vm.expectRevert(abi.encodeWithSelector(EndTimeBeforeStartTime.selector));
        usualSP.startRewardDistribution(100, block.timestamp + 1, block.timestamp);
    }

    function testStartRewardDistributionRevertIfStartTimeIsInPast() public {
        vm.prank(address(distributionModule));
        skip(1 days);
        vm.expectRevert(abi.encodeWithSelector(StartTimeInPast.selector));
        usualSP.startRewardDistribution(100, block.timestamp - 1 days, block.timestamp);
    }

    // 10.2 Testing basic flows //

    function testStartRewardDistributionEmitEvent(uint256 rewardAmount) public {
        rewardAmount = bound(rewardAmount, 1e18, USUALS_TOTAL_SUPPLY);
        deal(address(usualToken), address(distributionModule), rewardAmount);
        vm.startPrank(address(distributionModule));
        usualToken.approve(address(usualSP), rewardAmount);

        uint256 duration = block.timestamp + 1 days - block.timestamp;
        uint256 realRewardAmount = rewardAmount / duration * duration;

        vm.expectEmit();
        emit RewardPeriodStarted(realRewardAmount, block.timestamp, block.timestamp + 1 days);
        usualSP.startRewardDistribution(rewardAmount, block.timestamp, block.timestamp + 1 days);

        vm.stopPrank();
    }

    function testStartRewardDistributionWithoutSupply() public {
        vm.mockCall(
            address(usualS), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(0)
        );

        deal(address(usualToken), address(distributionModule), USUALS_TOTAL_SUPPLY);
        vm.startPrank(address(distributionModule));
        usualToken.approve(address(usualSP), USUALS_TOTAL_SUPPLY);
        usualSP.startRewardDistribution(100e18, block.timestamp, block.timestamp + 1 days);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            11. Getters 
    //////////////////////////////////////////////////////////////*/

    // 11.1 Testing basic flows //

    function testGetStartDate() public {
        setupVestingWithOneYearCliff(100);
        assertEq(usualSP.getStartDate(), block.timestamp);
    }

    function testGetLiquidAllocation() public {
        setupVestingWithOneYearCliff(300e18);
        assertEq(usualSP.getLiquidAllocation(alice), 0);
        skip(ONE_YEAR);
        vm.startPrank(alice);
        assertEq(usualS.balanceOf(alice), 0);
        usualSP.claimOriginalAllocation();
        assertApproxEqAbs(usualS.balanceOf(alice), 100e18, 1e2);
        usualS.transfer(bob, usualS.balanceOf(alice) / 2);
        assertEq(usualSP.getLiquidAllocation(alice), 0);
        assertEq(usualSP.getLiquidAllocation(bob), 0);
        usualS.approve(address(usualSP), usualS.balanceOf(bob));
        usualSP.stake(usualS.balanceOf(bob));
        vm.stopPrank();
        vm.startPrank(bob);
        usualS.approve(address(usualSP), usualS.balanceOf(bob));
        usualSP.stake(usualS.balanceOf(bob));
        vm.stopPrank();
        assertApproxEqAbs(usualSP.getLiquidAllocation(alice), 50e18, 1e2);
        assertApproxEqAbs(usualSP.getLiquidAllocation(bob), 50e18, 1e2);
    }

    function testBalanceOf(uint256 amount) public {
        amount = bound(amount, 1e18, USUALS_TOTAL_SUPPLY / 2);
        setupVestingWithOneYearCliff(amount);

        assertEq(usualSP.balanceOf(alice), amount);
        assertEq(usualSP.balanceOf(bob), amount);
    }

    function testGetTotalStaked() public view {
        assertEq(usualSP.totalStaked(), USUALS_TOTAL_SUPPLY);
    }

    function getDuration() public view {
        uint256 duration = usualSP.getDuration();
        assertEq(duration, VESTING_DURATION_THREE_YEARS);
    }

    function testGetCliffDuration() public {
        setupVestingWithOneYearCliff(100);
        assertEq(usualSP.getCliffDuration(alice), ONE_YEAR);
    }

    function testGetClaimableAmount() public {
        setupVestingWithOneYearCliff(100);
        vm.expectRevert(abi.encodeWithSelector(NotClaimableYet.selector));
        usualSP.getClaimableOriginalAllocation(alice);

        skip(VESTING_DURATION_THREE_YEARS);
        assertEq(usualSP.getClaimableOriginalAllocation(alice), 100);
    }

    function testGetOriginalClaimedAmount() public {
        setupVestingWithOneYearCliff(100);

        skip(VESTING_DURATION_THREE_YEARS);

        vm.startPrank(alice);
        usualSP.claimOriginalAllocation();

        assertEq(usualSP.getClaimedAllocation(alice), 100);
    }

    function testGetRewardRate(uint256 rewardAmount) public {
        rewardAmount = bound(rewardAmount, 1e18, USUALS_TOTAL_SUPPLY / 2);
        deal(address(usualToken), address(distributionModule), rewardAmount);

        setupVestingWithOneYearCliff(100);
        skip(ONE_MONTH);
        assertEq(usualSP.getRewardRate(), 0);

        vm.startPrank(address(distributionModule));

        usualToken.approve(address(usualSP), rewardAmount);
        usualSP.startRewardDistribution(rewardAmount, block.timestamp, block.timestamp + 1 days);

        assertEq(usualSP.getRewardRate(), rewardAmount / 1 days);
    }

    /*//////////////////////////////////////////////////////////////
                        12. Real Life Scenario 
    //////////////////////////////////////////////////////////////*/

    // Alice and Bob are insiders with same allocation
    // Alice doesn't have a cliff, she has a linear vesting for 3 years
    // Bob has a cliff of 1 year, and a linear vesting for 2 years
    // After 1 year, Alice and Bob should have claimed 1/3 of their allocation
    // Alice claims all her allocation and sends the USUALS to Bob
    // Bob stakes all his USUALS
    // Bob claims his reward

    function testVestingStakingClaimingReward(uint256 totalAllocation, uint256 rewardAmount)
        public
    {
        totalAllocation = bound(totalAllocation, 1e18, USUALS_TOTAL_SUPPLY / 2);
        rewardAmount = bound(rewardAmount, 1e18, USUALS_TOTAL_SUPPLY / 2);
        // Setup
        address[] memory recipient = new address[](2);
        recipient[0] = alice;
        recipient[1] = bob;
        uint256[] memory allocation = new uint256[](2);
        allocation[0] = totalAllocation;
        allocation[1] = totalAllocation;
        uint256[] memory cliffDurations = new uint256[](2);
        cliffDurations[0] = 0;
        cliffDurations[1] = ONE_YEAR;

        setupVesting(recipient, allocation, cliffDurations);

        skip(ONE_YEAR / 2);

        vm.startPrank(alice);
        usualSP.claimOriginalAllocation();
        assertApproxEqAbs(usualS.balanceOf(alice), totalAllocation / 6, 1e2);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(NotClaimableYet.selector));
        usualSP.claimOriginalAllocation();
        vm.stopPrank();

        skip(ONE_YEAR / 2);

        vm.startPrank(alice);
        usualSP.claimOriginalAllocation();
        assertApproxEqAbs(usualS.balanceOf(alice), totalAllocation / 3, 1e2);
        usualS.transfer(bob, usualS.balanceOf(alice));
        vm.stopPrank();

        vm.startPrank(bob);
        usualSP.claimOriginalAllocation();
        assertApproxEqAbs(
            usualS.balanceOf(bob), totalAllocation.mulDiv(2, 3, Math.Rounding.Floor), 1e2
        );

        usualS.approve(address(usualSP), usualS.balanceOf(bob));
        usualSP.stake(usualS.balanceOf(bob));
        assertApproxEqAbs(usualSP.balanceOf(bob), totalAllocation + totalAllocation / 3, 1e2);
        vm.stopPrank();

        skip(ONE_YEAR * 2);
        deal(address(usualToken), address(distributionModule), rewardAmount);

        vm.startPrank(address(distributionModule));
        usualToken.approve(address(usualSP), rewardAmount);
        usualSP.startRewardDistribution(rewardAmount, block.timestamp, block.timestamp + 1 days);
        vm.stopPrank();

        skip(1 days);

        vm.startPrank(bob);
        usualSP.claimReward();
        uint256 oneThirdAllocation = totalAllocation / 3;
        uint256 reward = rewardAmount.mulDiv(
            totalAllocation, USUALS_TOTAL_SUPPLY, Math.Rounding.Floor
        ) + rewardAmount.mulDiv(oneThirdAllocation, USUALS_TOTAL_SUPPLY, Math.Rounding.Floor);
        assertApproxEqAbs(usualToken.balanceOf(bob), reward, 1e6);
        vm.stopPrank();
    }

    function testClaimRewardRightAfterStaking() public {
        setupVestingWithOneYearCliff(USUALS_TOTAL_SUPPLY / 2);
        skip(VESTING_DURATION_THREE_YEARS);

        vm.prank(alice);
        usualSP.claimOriginalAllocation();
        assertEq(usualS.balanceOf(alice), USUALS_TOTAL_SUPPLY / 2);

        vm.startPrank(address(distributionModule));
        deal(address(usualToken), address(distributionModule), 500e18);
        usualToken.approve(address(usualSP), 500e18);
        usualSP.startRewardDistribution(500e18, block.timestamp, block.timestamp + 1 days);
        vm.stopPrank();

        skip(1 days);

        vm.startPrank(alice);
        usualS.approve(address(usualSP), usualS.balanceOf(alice));
        usualSP.stake(usualS.balanceOf(alice));
        usualSP.claimReward();
        assertEq(usualToken.balanceOf(alice), 0);

        skip(1 days);
        usualSP.claimReward();
        assertEq(usualToken.balanceOf(alice), 0);
    }

    function testStartRewardDistributionDuringOnGoingRewardPeriod() public {
        setupVestingWithOneYearCliff(USUALS_TOTAL_SUPPLY / 2);
        skip(VESTING_DURATION_THREE_YEARS);

        deal(address(usualToken), address(distributionModule), 100e18);

        vm.startPrank(address(distributionModule));
        usualToken.approve(address(usualSP), 100e18);
        usualSP.startRewardDistribution(100e18, block.timestamp, block.timestamp + 1 days);
        skip(1 days / 2);
        vm.expectRevert(abi.encodeWithSelector(AlreadyStarted.selector));
        usualSP.startRewardDistribution(100e18, block.timestamp, block.timestamp + 1 days);
    }

    function testMultipleUsersWithDifferentAllocationsAndCliffs() public {
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = carol;

        uint256[] memory allocations = new uint256[](3);
        allocations[0] = 1000e18;
        allocations[1] = 2000e18;
        allocations[2] = 3000e18;

        uint256[] memory cliffs = new uint256[](3);
        cliffs[0] = 6 * ONE_MONTH;
        cliffs[1] = ONE_YEAR;
        cliffs[2] = 18 * ONE_MONTH;

        vm.prank(usualSPOperator);
        usualSP.allocate(users, allocations, cliffs);

        // Fast forward 6 months
        skip(6 * ONE_MONTH);

        vm.prank(alice);
        usualSP.claimOriginalAllocation();
        assertApproxEqAbs(usualS.balanceOf(alice), 167e18, 1e18); // ~1/6 of allocation

        // Fast forward another 6 months
        skip(6 * ONE_MONTH);

        vm.prank(bob);
        usualSP.claimOriginalAllocation();
        assertApproxEqAbs(usualS.balanceOf(bob), 667e18, 1e18); // ~1/3 of allocation

        vm.prank(alice);
        usualSP.claimOriginalAllocation();
        assertApproxEqAbs(usualS.balanceOf(alice), 333e18, 1e18); // ~1/3 of allocation

        // Fast forward to end of vesting
        skip(2 * ONE_YEAR);

        vm.prank(carol);
        usualSP.claimOriginalAllocation();
        assertEq(usualS.balanceOf(carol), 3000e18); // Full allocation
    }

    function testStakingAndUnWrappingDuringVestingPeriod() public {
        setupVestingWithOneYearCliff(1000e18);
        skip(ONE_YEAR);

        vm.startPrank(alice);
        usualSP.claimOriginalAllocation();
        uint256 claimedAmount = usualS.balanceOf(alice);
        usualS.approve(address(usualSP), claimedAmount);
        usualSP.stake(claimedAmount);

        assertEq(usualSP.balanceOf(alice), 1000e18);
        assertEq(usualS.balanceOf(alice), 0);

        skip(ONE_YEAR);

        usualSP.unstake(claimedAmount);

        assertApproxEqAbs(usualSP.balanceOf(alice), 1000e18 - claimedAmount, 1e18);
        assertApproxEqAbs(usualS.balanceOf(alice), claimedAmount, 1e18);

        vm.stopPrank();
    }

    function testClaimingRewardsAcrossMultipleDistributionPeriods() public {
        setupVestingWithOneYearCliff(1000e18);
        skip(ONE_YEAR);

        vm.prank(alice);
        usualSP.claimOriginalAllocation();

        for (uint256 i = 0; i < 3; i++) {
            uint256 rewardAmount = 100e18;
            deal(address(usualToken), address(distributionModule), rewardAmount);

            vm.startPrank(address(distributionModule));
            usualToken.approve(address(usualSP), rewardAmount);
            usualSP.startRewardDistribution(rewardAmount, block.timestamp, block.timestamp + 1 days);
            vm.stopPrank();

            skip(1 days);

            if (i != 2) {
                skip(1 days); // Gap between distribution periods
            }
        }

        vm.prank(alice);
        uint256 totalReward = usualSP.claimReward();
        uint256 expectedReward = 300e18 * (1000e24 / USUALS_TOTAL_SUPPLY);

        assertApproxEqAbs(totalReward, expectedReward / 1e6, 1e18); // Should be close to total rewards distributed
    }

    function testTransferringStakedTokensBetweenUsers() public {
        setupVestingWithAliceAndBob(1000e18, 1000e18, 0, 0);

        skip(3 * ONE_YEAR);

        vm.prank(alice);
        usualSP.claimOriginalAllocation();

        vm.prank(bob);
        usualSP.claimOriginalAllocation();

        vm.prank(alice);
        usualS.transfer(bob, 500e18);

        assertEq(usualS.balanceOf(alice), 500e18);
        assertEq(usualS.balanceOf(bob), 1500e18);

        vm.startPrank(bob);
        usualS.approve(address(usualSP), 1500e18);
        usualSP.stake(1500e18);

        assertEq(usualSP.balanceOf(bob), 1500e18);
    }

    function testPausingAndUnpausingDuringVestingAndRewardPeriods() public {
        setupVestingWithOneYearCliff(1000e18);
        skip(ONE_YEAR);

        vm.prank(pauser);
        usualSP.pause();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        usualSP.claimOriginalAllocation();

        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        usualSP.stake(100);

        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        usualSP.claimReward();
        vm.stopPrank();

        vm.prank(admin);
        usualSP.unpause();

        vm.prank(alice);
        usualSP.claimOriginalAllocation();

        assertApproxEqAbs(usualS.balanceOf(alice), 333e18, 1e18);
    }

    function testReduceAllocationAfterClaimRevert() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory allocations = new uint256[](1);
        allocations[0] = 100e18;
        uint256[] memory cliffDurations = new uint256[](1);
        cliffDurations[0] = 100 days;

        setupVesting(recipients, allocations, cliffDurations);

        skip(100 days);

        // Alice partially claims her allocation
        vm.prank(alice);
        usualSP.claimOriginalAllocation();

        assertGt(usualS.balanceOf(alice), 0);

        skip(10 days);

        // Alice's allocation is reduced
        allocations[0] = 0;
        vm.expectRevert(abi.encodeWithSelector(CannotReduceAllocation.selector));
        setupVesting(recipients, allocations, cliffDurations);
    }

    function testClaimRewardLossTotalSupply_poc() public {
        uint256 rewardAmount = 100e18;
        uint256 stakedAmount = usualS.totalSupply() / 2;
        skip(ONE_MONTH);
        // Return entire vested/staked supply
        vm.startPrank(address(usualSP));
        usualS.transfer(alice, stakedAmount);
        usualS.transfer(bob, stakedAmount);
        vm.stopPrank();
        // Start reward distribution
        vm.startPrank(address(distributionModule));
        deal(address(usualToken), address(distributionModule), rewardAmount);
        usualToken.approve(address(usualSP), rewardAmount);
        usualSP.startRewardDistribution(rewardAmount, block.timestamp, block.timestamp + 1 days);
        vm.stopPrank();
        uint256 snap = vm.snapshot();
        // Alice stakes
        vm.startPrank(alice);
        usualS.approve(address(usualSP), stakedAmount);
        usualSP.stake(stakedAmount);
        vm.stopPrank();
        // Bob stakes
        vm.startPrank(bob);
        usualS.approve(address(usualSP), stakedAmount);
        usualSP.stake(stakedAmount);
        vm.stopPrank();

        skip(1 days);
        vm.startPrank(alice);
        usualSP.unstake(stakedAmount);
        usualSP.claimReward();
        vm.stopPrank();
        assertApproxEqRel(usualToken.balanceOf(alice), rewardAmount / 2, 0.0001e18);
        vm.startPrank(bob);
        usualSP.unstake(stakedAmount);
        usualSP.claimReward();
        vm.stopPrank();
        assertApproxEqRel(usualToken.balanceOf(bob), rewardAmount / 2, 0.0001e18);
        // Re-simulate, but this time Alice is the sole staker
        vm.revertTo(snap);
        // Alice stakes
        vm.startPrank(alice);
        usualS.approve(address(usualSP), stakedAmount);
        usualSP.stake(stakedAmount);
        vm.stopPrank();
        // The entire staked amount is owned by Alice
        assertEq(usualS.balanceOf(address(usualSP)), stakedAmount);
        skip(1 days);
        vm.startPrank(alice);
        usualSP.unstake(stakedAmount);
        usualSP.claimReward();
        vm.stopPrank();
        assertApproxEqRel(usualToken.balanceOf(alice), rewardAmount, 0.0001e18);
    }

    function testClaimRewardLossTotalSupplyFuzz(uint256 rewardAmount, uint256 stakedAmount)
        public
    {
        rewardAmount = bound(rewardAmount, 10_000e18, 5e24);
        stakedAmount = bound(stakedAmount, 1e18, USUALS_TOTAL_SUPPLY / 4);

        address[] memory users = new address[](4);
        users[0] = alice;
        users[1] = bob;
        users[2] = carol;
        users[3] = david;

        uint256[] memory allocations = new uint256[](4);
        allocations[0] = stakedAmount;
        allocations[1] = stakedAmount;
        allocations[2] = stakedAmount;
        allocations[3] = stakedAmount;

        setupVesting(users, allocations, new uint256[](4));

        skip(ONE_MONTH);

        vm.startPrank(address(distributionModule));
        deal(address(usualToken), address(distributionModule), rewardAmount);
        usualToken.approve(address(usualSP), rewardAmount);
        usualSP.startRewardDistribution(rewardAmount, block.timestamp, block.timestamp + 1 days);
        vm.stopPrank();

        skip(1 days);

        uint256 snap = vm.snapshot();

        vm.startPrank(alice);
        usualSP.claimReward();
        vm.stopPrank();

        vm.startPrank(bob);
        usualSP.claimReward();
        vm.stopPrank();

        vm.startPrank(carol);
        usualSP.claimReward();
        vm.stopPrank();

        vm.startPrank(david);
        usualSP.claimReward();
        vm.stopPrank();

        assertApproxEqRel(
            usualToken.balanceOf(alice),
            rewardAmount * (stakedAmount * 1e32 / usualSP.totalStaked()) / 1e32,
            1e18
        );

        assertApproxEqRel(
            usualToken.balanceOf(bob),
            rewardAmount * (stakedAmount * 1e32 / usualSP.totalStaked()) / 1e32,
            1e18
        );

        assertApproxEqRel(
            usualToken.balanceOf(carol),
            rewardAmount * (stakedAmount * 1e32 / usualSP.totalStaked()) / 1e32,
            1e18
        );

        assertApproxEqRel(
            usualToken.balanceOf(david),
            rewardAmount * (stakedAmount * 1e32 / usualSP.totalStaked()) / 1e32,
            1e18
        );

        vm.revertTo(snap);

        vm.startPrank(alice);
        usualSP.claimOriginalAllocation();
        usualSP.claimReward();
        vm.stopPrank();

        vm.startPrank(bob);
        usualSP.claimOriginalAllocation();
        usualSP.claimReward();
        vm.stopPrank();

        vm.startPrank(carol);
        usualSP.claimOriginalAllocation();
        usualSP.claimReward();
        vm.stopPrank();

        vm.startPrank(david);
        usualSP.claimOriginalAllocation();
        usualSP.claimReward();
        vm.stopPrank();

        assertApproxEqRel(
            usualToken.balanceOf(alice),
            rewardAmount * (stakedAmount * 1e32 / usualSP.totalStaked()) / 1e32,
            1e18
        );

        assertApproxEqRel(
            usualToken.balanceOf(bob),
            rewardAmount * (stakedAmount * 1e32 / usualSP.totalStaked()) / 1e32,
            1e18
        );

        assertApproxEqRel(
            usualToken.balanceOf(carol),
            rewardAmount * (stakedAmount * 1e32 / usualSP.totalStaked()) / 1e32,
            1e18
        );

        assertApproxEqRel(
            usualToken.balanceOf(david),
            rewardAmount * (stakedAmount * 1e32 / usualSP.totalStaked()) / 1e32,
            1e18
        );
    }

    function testClaimRewardShouldWork_audit() public {
        uint256 rewardAmount = 100e18;
        uint256 vestedAmount = 300e18;

        setupStartOneDayRewardDistribution(rewardAmount);
        setupVestingWithOneYearCliff(vestedAmount);

        // Vested amount is seen as staked usualS balance
        assertEq(usualSP.balanceOf(alice), vestedAmount);

        // Skip to end
        skip(5 * 365 days);

        uint256 rate = rewardAmount / 1 days;
        uint256 rewardPerToken = rate * 1 days * 1e24 / usualSP.totalStaked();
        uint256 claimableRewardAmount = vestedAmount * rewardPerToken / 1e24;

        vm.startPrank(alice);

        // Scenario 1:
        // Alice first claims her $Usual rewards
        // Alice then claims her $UsualS allocation
        uint256 snap = vm.snapshot();

        usualSP.claimReward();
        usualSP.claimOriginalAllocation();

        assertEq(usualS.balanceOf(alice), vestedAmount);
        assertEq(usualToken.balanceOf(alice), claimableRewardAmount);

        // Scenario 2:
        // Alice first claims her $UsualS allocation
        // Alice then claims her $Usual rewards
        vm.revertTo(snap);

        usualSP.claimOriginalAllocation();
        usualSP.claimReward();

        assertEq(usualS.balanceOf(alice), vestedAmount);
        assertEq(usualToken.balanceOf(alice), claimableRewardAmount);
    }

    function testAllocationAfterStartAudit() public {
        uint256 rewardAmount = 100e18;
        uint256 vestedAmount = usualS.totalSupply() / 2;

        // Simulate 100 days of rewards passing
        for (uint256 i; i < 100; i++) {
            setupStartOneDayRewardDistribution(rewardAmount);
            skip(1 days);
        }

        // Set up a vested allocation for Alice
        setupVestingWithOneYearCliff(vestedAmount);

        // Alice claims her staking reward
        vm.prank(alice);
        usualSP.claimReward();

        // Alice hasn't spent any time actively staking or kept any of her original
        // allocation unclaimed in the staking contract, so she shouldn't have received
        // any Usual rewards
        assertEq(usualToken.balanceOf(alice), 0);

        // Simulate again 100 days of rewards passing
        for (uint256 i; i < 100; i++) {
            setupStartOneDayRewardDistribution(rewardAmount);
            skip(1 days);
            vm.prank(alice);
            usualSP.claimReward();
            assertApproxEqAbs(usualToken.balanceOf(alice), rewardAmount / 2 * (i + 1), 0.001e18);
        }
    }
}
