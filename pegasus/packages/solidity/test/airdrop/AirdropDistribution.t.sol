// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SetupTest} from "../setup.t.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {Pausable} from "openzeppelin-contracts/utils/Pausable.sol";
import {AirdropDistribution} from "src/airdrop/AirdropDistribution.sol";
import {IAirdropDistribution} from "src/interfaces/airdrop/IAirdropDistribution.sol";
import {Usd0PP} from "src/token/Usd0PP.sol";
import {IOracle} from "src/interfaces/oracles/IOracle.sol";

import {
    BASIS_POINT_BASE,
    AIRDROP_INITIAL_START_TIME,
    END_OF_EARLY_UNLOCK_PERIOD,
    FIRST_AIRDROP_VESTING_CLAIMING_DATE,
    SECOND_AIRDROP_VESTING_CLAIMING_DATE,
    THIRD_AIRDROP_VESTING_CLAIMING_DATE,
    FOURTH_AIRDROP_VESTING_CLAIMING_DATE,
    FIFTH_AIRDROP_VESTING_CLAIMING_DATE,
    SIXTH_AIRDROP_VESTING_CLAIMING_DATE,
    CONTRACT_TREASURY,
    EARLY_BOND_UNLOCK_ROLE
} from "src/constants.sol";
import {
    NullContract,
    NotAuthorized,
    NullMerkleRoot,
    InvalidProof,
    AmountIsZero,
    AmountTooBig,
    BeginInPast,
    NotClaimableYet,
    NothingToClaim,
    SameValue,
    InitialStartTimeAfterVestingStartTime,
    NullAddress,
    OutOfBounds,
    InvalidInputArraysLength,
    AirdropVoided
} from "src/errors.sol";

contract AirdropDistributionTest is SetupTest {
    using Math for uint256;

    event MerkleRootSet(bytes32 indexed merkleRoot);
    event PenaltyPercentagesSet(
        address[] indexed accounts, uint256[] indexed penaltyPercentages, uint256 indexed month
    );
    event Claimed(address indexed account, uint256 indexed amount);

    /*//////////////////////////////////////////////////////////////
                              0. CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // Alice

    function _aliceProof() internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](3);
        proof[0] = bytes32(0x3cf22c24b355aa63177bc36f88b2da12593d6062a80d316be2dfa393b88f0eef);
        proof[1] = bytes32(0xb3d293e62d7f4ea38023d09e214ed8e11dd246894f7757faafaf33f011ce38ce);
        proof[2] = bytes32(0x57257d357b0b1184d8f95c2d207d8e58908bc7fb2d133000fd2e5910e72efc29);
        return proof;
    }

    uint256 public aliceAmount = 4_866_160_317_000_000_000_000_000_000;

    // Bob

    function _bobProof() internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(0x66e25d24a7c76dffea66de075198c5bb8e1a9099baca379244ea8840bb1bb76e);
        proof[1] = bytes32(0x11f18600d2ce1eb1a2a12222bdeaa1d81aab89e2f6a48efec7ae0f09ff8a54cf);
        return proof;
    }

    uint256 public bobAmount = 167_600_175_000_000_000_000_000_000;

    // Carol

    function _carolProof() internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(0x8b4bdaea5106c0df6e61437f524a989312961469b0c56c882783bffb17897f50);
        proof[1] = bytes32(0x11f18600d2ce1eb1a2a12222bdeaa1d81aab89e2f6a48efec7ae0f09ff8a54cf);
        return proof;
    }

    uint256 public carolAmount = 18_450_169_000_000_000_000_000_000;

    // David

    function _davidProof() internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(0x7b2c541bee9300ab1e631eea1f40cff6c334aee26956f18643853f07adca1835);
        proof[1] = bytes32(0x57257d357b0b1184d8f95c2d207d8e58908bc7fb2d133000fd2e5910e72efc29);
        return proof;
    }

    uint256 public davidAmount = 62_497_000_000_000_000_000_000;

    // Jack

    function _jackProof() internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](3);
        proof[0] = bytes32(0x1646f9ae8eec9ab68927ce6ce00614b2a1e71fc726eda02a5f6ad4b02883e886);
        proof[1] = bytes32(0xb3d293e62d7f4ea38023d09e214ed8e11dd246894f7757faafaf33f011ce38ce);
        proof[2] = bytes32(0x57257d357b0b1184d8f95c2d207d8e58908bc7fb2d133000fd2e5910e72efc29);
        return proof;
    }

    uint256 public jackAmount = 1_000_000_000_000_000_000;

    /*//////////////////////////////////////////////////////////////
                            1. SETUP & HELPERS
    //////////////////////////////////////////////////////////////*/

    /*
        alice = 0x6a8b32cb656559c0fC49cD7Db3ce48C074A7abe3 ; 4866160317000000000000000000 ; true
        bob = 0x02A02da2CB9795931fb68C8ae3d6237d2dD8e70e ; 167600175000000000000000000 ; true
        carol = 0xa000c80DCB9Cb742Cb37Fbe410E73c8C7A0702c1 ; 18450169000000000000000000 ; true
        david = 0xE18526A1F8D22bf747a6234eEAE1139797C49369 ; 62497000000000000000000 ; false
        jack = 0x8D1cbf0a75D63e63a5C887EC33ed9c2A5458a614 ; 1000000000000000000 ; false
    */
    function setUp() public override {
        super.setUp();

        vm.startPrank(airdropOperator);
        bytes32 root = 0xec468d23c3cf5371c09000d0cff5b87a7da37382679735385416be5686af734a;
        airdropDistribution.setMerkleRoot(root);
        vm.stopPrank();

        vm.warp(AIRDROP_INITIAL_START_TIME);
    }

    uint256[] public vestingSchedule = [
        FIRST_AIRDROP_VESTING_CLAIMING_DATE,
        SECOND_AIRDROP_VESTING_CLAIMING_DATE,
        THIRD_AIRDROP_VESTING_CLAIMING_DATE,
        FOURTH_AIRDROP_VESTING_CLAIMING_DATE,
        FIFTH_AIRDROP_VESTING_CLAIMING_DATE,
        SIXTH_AIRDROP_VESTING_CLAIMING_DATE
    ];

    /*//////////////////////////////////////////////////////////////
                            2. INITIALIZER
    //////////////////////////////////////////////////////////////*/

    // 2.1 Testing revert properties //

    function testInitializerShouldFailWhenNullContract() external {
        _resetInitializerImplementation(address(airdropDistribution));
        vm.expectRevert(abi.encodeWithSelector(NullContract.selector));
        airdropDistribution.initialize(address(0));
    }

    // 2.2 Testing basic flows //

    function testInitializeShouldWork() external {
        _resetInitializerImplementation(address(airdropDistribution));
        vm.startPrank(admin);
        airdropDistribution.initialize(address(registryContract));
        vm.stopPrank();
        assertEq(
            airdropDistribution.getVestingDuration(),
            SIXTH_AIRDROP_VESTING_CLAIMING_DATE - AIRDROP_INITIAL_START_TIME
        );
    }

    function testConstructorShouldWork() external {
        IAirdropDistribution engine = new AirdropDistribution();
        assertTrue(address(engine) != address(0));
    }

    /*//////////////////////////////////////////////////////////////
                          3. CLAIM AIRDROPS
    //////////////////////////////////////////////////////////////*/

    // 3.1 Testing revert properties //

    function testClaimShouldFailWhenNullAddress() external {
        bytes32[] memory nullProof = new bytes32[](0);
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        airdropDistribution.claim(address(0), true, 0, nullProof);
    }

    function testClaimShouldFailWhenAmountIsZero() external {
        bytes32[] memory nullProof = new bytes32[](0);
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        airdropDistribution.claim(alice, true, 0, nullProof);
    }

    function testClaimShouldFailWhenProofIsInvalid() external {
        bytes32[] memory nullProof = new bytes32[](0);
        vm.expectRevert(abi.encodeWithSelector(InvalidProof.selector));
        airdropDistribution.claim(alice, true, 1, nullProof);
    }

    function testClaimShouldRevertIfPaused() external {
        vm.startPrank(pauser);
        airdropDistribution.pause();
        vm.stopPrank();

        bytes32[] memory nullProof = new bytes32[](0);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        airdropDistribution.claim(alice, true, 1, nullProof);
    }

    function testClaimMonthlyShouldFailIfNothingToClaim() external {
        bytes32[] memory aliceProof = _aliceProof();
        for (uint256 i = 0; i <= 5; i++) {
            vm.warp(vestingSchedule[i]);
            vm.startPrank(alice);
            airdropDistribution.claim(alice, true, aliceAmount, aliceProof);
            vm.expectRevert(abi.encodeWithSelector(NothingToClaim.selector));
            airdropDistribution.claim(alice, true, aliceAmount, aliceProof);
            vm.stopPrank();
        }
    }

    function testClaimDuringVestingShouldFailIfNothingToClaim() external {
        bytes32[] memory aliceProof = _aliceProof();
        skip(182 days);
        vm.startPrank(alice);
        airdropDistribution.claim(alice, true, aliceAmount, aliceProof);

        vm.expectRevert(abi.encodeWithSelector(NothingToClaim.selector));
        airdropDistribution.claim(alice, true, aliceAmount, aliceProof);
        vm.stopPrank();
    }

    function testClaimAfterVestingShouldFailIfNothingToClaim() external {
        bytes32[] memory aliceProof = _aliceProof();
        skip(182 days);
        vm.startPrank(alice);
        airdropDistribution.claim(alice, true, aliceAmount, aliceProof);

        vm.expectRevert(abi.encodeWithSelector(NothingToClaim.selector));
        airdropDistribution.claim(alice, true, aliceAmount, aliceProof);
        vm.stopPrank();
    }

    function testClaimShouldRevertIfNotStarted() external {
        _resetInitializerImplementation(address(airdropTaxCollector));
        airdropTaxCollector.initialize(address(registryContract));
        _resetInitializerImplementation(address(airdropDistribution));
        vm.startPrank(admin);
        airdropDistribution.initialize(address(registryContract));
        vm.stopPrank();

        vm.warp(AIRDROP_INITIAL_START_TIME - 1);

        bytes32[] memory aliceProof = _aliceProof();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotClaimableYet.selector));
        airdropDistribution.claim(alice, true, aliceAmount, aliceProof);
    }

    function testClaimRevertDuringFirstMonth() external {
        bytes32[] memory aliceProof = _aliceProof();
        vm.warp(FIRST_AIRDROP_VESTING_CLAIMING_DATE - 1);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotClaimableYet.selector));
        airdropDistribution.claim(alice, true, aliceAmount, aliceProof);
    }

    // 3.2 Testing basic flows //

    function testClaimShouldWorkWithVesting() external {
        bytes32[] memory aliceProof = _aliceProof();
        bytes32[] memory bobProof = _bobProof();
        bytes32[] memory carolProof = _carolProof();
        for (uint256 i = 0; i <= 5; i++) {
            vm.warp(vestingSchedule[i]);
            vm.prank(alice);
            airdropDistribution.claim(alice, true, aliceAmount, aliceProof);
            assertApproxEqRel(usualToken.balanceOf(alice), aliceAmount.mulDiv(i + 1, 6), 1e2);
            assertApproxEqRel(
                airdropDistribution.getClaimed(alice), aliceAmount.mulDiv(i + 1, 6), 1e2
            );

            vm.prank(bob);
            airdropDistribution.claim(bob, true, bobAmount, bobProof);
            assertApproxEqRel(usualToken.balanceOf(bob), bobAmount.mulDiv(i + 1, 6), 1e2);
            assertApproxEqRel(airdropDistribution.getClaimed(bob), bobAmount.mulDiv(i + 1, 6), 1e2);

            vm.prank(carol);
            airdropDistribution.claim(carol, true, carolAmount, carolProof);
            assertApproxEqRel(usualToken.balanceOf(carol), carolAmount.mulDiv(i + 1, 6), 1e2);
            assertApproxEqRel(
                airdropDistribution.getClaimed(carol), carolAmount.mulDiv(i + 1, 6), 1e2
            );
        }
    }

    function testClaimShouldWorkWithoutVesting() external {
        bytes32[] memory davidProof = _davidProof();
        bytes32[] memory jackProof = _jackProof();

        vm.prank(david);
        airdropDistribution.claim(david, false, davidAmount, davidProof);
        assertApproxEqRel(usualToken.balanceOf(david), davidAmount, 1e2);
        assertApproxEqRel(airdropDistribution.getClaimed(david), davidAmount, 1e2);

        vm.prank(jack);
        airdropDistribution.claim(jack, false, jackAmount, jackProof);
        assertApproxEqRel(usualToken.balanceOf(jack), jackAmount, 1e2);
    }

    function testClaimForAnotherAccountShouldWork() external {
        bytes32[] memory aliceProof = _aliceProof();
        for (uint256 i = 0; i <= 5; i++) {
            vm.warp(vestingSchedule[i]);
            vm.prank(bob);
            airdropDistribution.claim(alice, true, aliceAmount, aliceProof);
            assertApproxEqRel(usualToken.balanceOf(alice), aliceAmount.mulDiv(i + 1, 6), 1e2);
            assertApproxEqRel(
                airdropDistribution.getClaimed(alice), aliceAmount.mulDiv(i + 1, 6), 1e2
            );
        }
    }

    function testClaimShouldEmitEvent() external {
        bytes32[] memory aliceProof = _aliceProof();

        skip(182 days);

        vm.prank(alice);
        vm.expectEmit();
        emit Claimed(alice, aliceAmount);
        airdropDistribution.claim(alice, true, aliceAmount, aliceProof);
    }

    function testClaimWithPenaltyShouldWork(uint256 penaltyAlice) external {
        penaltyAlice = bound(penaltyAlice, 1, BASIS_POINT_BASE);
        uint256 penaltyBob = BASIS_POINT_BASE + 1 - penaltyAlice;
        bytes32[] memory aliceProof = _aliceProof();
        bytes32[] memory bobProof = _bobProof();

        uint256[] memory penalties = new uint256[](2);
        penalties[0] = penaltyAlice;
        penalties[1] = penaltyBob;

        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        vm.startPrank(airdropPenaltyOperator);
        airdropDistribution.setPenaltyPercentages(penalties, accounts, 1);
        vm.stopPrank();

        skip(182 days);

        vm.prank(alice);
        airdropDistribution.claim(alice, true, aliceAmount, aliceProof);
        uint256 oneSixthAlice = aliceAmount / 6;
        assertApproxEqRel(
            usualToken.balanceOf(alice),
            aliceAmount - oneSixthAlice.mulDiv(penaltyAlice, BASIS_POINT_BASE),
            1e2
        );

        vm.prank(bob);
        airdropDistribution.claim(bob, true, bobAmount, bobProof);
        uint256 oneSixthBob = bobAmount / 6;
        assertApproxEqRel(
            usualToken.balanceOf(bob),
            bobAmount - oneSixthBob.mulDiv(penaltyBob, BASIS_POINT_BASE),
            1e2
        );
    }

    function testClaimWithPenaltyShouldWorkWithVesting(uint256 penaltyAlice) external {
        penaltyAlice = bound(penaltyAlice, 1, BASIS_POINT_BASE - 1);
        uint256 penaltyBob = BASIS_POINT_BASE - penaltyAlice;
        bytes32[] memory aliceProof = _aliceProof();
        bytes32[] memory bobProof = _bobProof();

        uint256[] memory penalties = new uint256[](2);
        penalties[0] = penaltyAlice;
        penalties[1] = penaltyBob;

        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        for (uint256 i = 0; i <= 5; i++) {
            vm.warp(vestingSchedule[i]);
            vm.startPrank(airdropPenaltyOperator);
            airdropDistribution.setPenaltyPercentages(penalties, accounts, i + 1);
            vm.stopPrank();

            vm.prank(alice);
            airdropDistribution.claim(alice, true, aliceAmount, aliceProof);
            uint256 oneSixthAlice = aliceAmount / 6;
            assertApproxEqRel(
                usualToken.balanceOf(alice),
                (oneSixthAlice - oneSixthAlice.mulDiv(penaltyAlice, BASIS_POINT_BASE)) * (i + 1),
                1e2
            );
            vm.prank(bob);
            airdropDistribution.claim(bob, true, bobAmount, bobProof);
            uint256 oneSixthBob = bobAmount / 6;
            assertApproxEqRel(
                usualToken.balanceOf(bob),
                (oneSixthBob - oneSixthBob.mulDiv(penaltyBob, BASIS_POINT_BASE)) * (i + 1),
                1e2
            );
        }

        assertApproxEqRel(
            usualToken.balanceOf(alice),
            aliceAmount - aliceAmount.mulDiv(penaltyAlice, BASIS_POINT_BASE),
            1e2
        );
        assertApproxEqRel(
            usualToken.balanceOf(bob),
            bobAmount - bobAmount.mulDiv(penaltyBob, BASIS_POINT_BASE),
            1e2
        );
    }

    function testClaimWorksWithDifferentPenalty(
        uint256 penaltyAliceFirstMonth,
        uint256 penaltyAliceSecondMonth,
        uint256 penaltyAliceThirdMonth,
        uint256 penaltyAliceFourthMonth,
        uint256 penaltyAliceFifthMonth
    ) external {
        bytes32[] memory aliceProof = _aliceProof();

        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        penaltyAliceFirstMonth = bound(penaltyAliceFirstMonth, 1, BASIS_POINT_BASE);
        uint256[] memory penaltiesFirstMonth = new uint256[](1);
        penaltiesFirstMonth[0] = penaltyAliceFirstMonth;

        penaltyAliceSecondMonth = bound(penaltyAliceSecondMonth, 10, BASIS_POINT_BASE);
        uint256[] memory penaltiesSecondMonth = new uint256[](1);
        penaltiesSecondMonth[0] = penaltyAliceSecondMonth;

        penaltyAliceThirdMonth = bound(penaltyAliceThirdMonth, 100, BASIS_POINT_BASE);
        uint256[] memory penaltiesThirdMonth = new uint256[](1);
        penaltiesThirdMonth[0] = penaltyAliceThirdMonth;

        penaltyAliceFourthMonth = bound(penaltyAliceFourthMonth, 1000, BASIS_POINT_BASE);
        uint256[] memory penaltiesFourthMonth = new uint256[](1);
        penaltiesFourthMonth[0] = penaltyAliceFourthMonth;

        penaltyAliceFifthMonth = bound(penaltyAliceFifthMonth, 5000, BASIS_POINT_BASE);
        uint256[] memory penaltiesFifthMonth = new uint256[](1);
        penaltiesFifthMonth[0] = penaltyAliceFifthMonth;

        vm.startPrank(airdropPenaltyOperator);
        airdropDistribution.setPenaltyPercentages(penaltiesFirstMonth, accounts, 1);
        airdropDistribution.setPenaltyPercentages(penaltiesSecondMonth, accounts, 2);
        airdropDistribution.setPenaltyPercentages(penaltiesThirdMonth, accounts, 3);
        airdropDistribution.setPenaltyPercentages(penaltiesFourthMonth, accounts, 4);
        airdropDistribution.setPenaltyPercentages(penaltiesFifthMonth, accounts, 5);
        vm.stopPrank();

        skip(182 days);

        vm.prank(alice);
        airdropDistribution.claim(alice, true, aliceAmount, aliceProof);
        uint256 oneSixthAlice = aliceAmount / 6;
        uint256 expectedRewardsFirstMonth =
            oneSixthAlice - oneSixthAlice.mulDiv(penaltyAliceFirstMonth, BASIS_POINT_BASE);
        uint256 expectedRewardsSecondMonth =
            oneSixthAlice - oneSixthAlice.mulDiv(penaltyAliceSecondMonth, BASIS_POINT_BASE);
        uint256 expectedRewardsThirdMonth =
            oneSixthAlice - oneSixthAlice.mulDiv(penaltyAliceThirdMonth, BASIS_POINT_BASE);
        uint256 expectedRewardsFourthMonth =
            oneSixthAlice - oneSixthAlice.mulDiv(penaltyAliceFourthMonth, BASIS_POINT_BASE);
        uint256 expectedRewardsFifthMonth =
            oneSixthAlice - oneSixthAlice.mulDiv(penaltyAliceFifthMonth, BASIS_POINT_BASE);

        uint256 totalRewards = expectedRewardsFirstMonth + expectedRewardsSecondMonth
            + expectedRewardsThirdMonth + expectedRewardsFourthMonth + expectedRewardsFifthMonth
            + oneSixthAlice;

        assertApproxEqRel(usualToken.balanceOf(alice), totalRewards, 1e2);
    }

    function testClaimWithFullPenaltyShouldWorkWithVesting() external {
        bytes32[] memory aliceProof = _aliceProof();
        bytes32[] memory bobProof = _bobProof();
        bytes32[] memory carolProof = _carolProof();
        uint256 penalty = BASIS_POINT_BASE;

        uint256[] memory penalties = new uint256[](3);
        penalties[0] = penalty;
        penalties[1] = penalty;
        penalties[2] = penalty;

        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = carol;

        for (uint256 i = 0; i <= 5; i++) {
            vm.warp(vestingSchedule[i]);
            vm.startPrank(airdropPenaltyOperator);
            airdropDistribution.setPenaltyPercentages(penalties, accounts, i + 1);
            vm.stopPrank();

            vm.prank(alice);
            vm.expectRevert(abi.encodeWithSelector(NothingToClaim.selector));
            airdropDistribution.claim(alice, true, aliceAmount, aliceProof);

            vm.prank(bob);
            vm.expectRevert(abi.encodeWithSelector(NothingToClaim.selector));
            airdropDistribution.claim(bob, true, bobAmount, bobProof);

            vm.prank(carol);
            vm.expectRevert(abi.encodeWithSelector(NothingToClaim.selector));
            airdropDistribution.claim(carol, true, carolAmount, carolProof);
        }

        assertEq(usualToken.balanceOf(alice), 0);
        assertEq(usualToken.balanceOf(bob), 0);
        assertEq(usualToken.balanceOf(carol), 0);
    }

    function testClaimWorksWithPenaltyForAnotherAccount() external {
        bytes32[] memory aliceProof = _aliceProof();
        bytes32[] memory bobProof = _bobProof();

        uint256 penaltyAlice = 10;
        uint256 penaltyBob = 10;

        uint256[] memory penalties = new uint256[](2);
        penalties[0] = penaltyAlice;
        penalties[1] = penaltyBob;

        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        for (uint256 i = 0; i <= 5; i++) {
            vm.warp(vestingSchedule[i]);
            vm.startPrank(airdropPenaltyOperator);
            airdropDistribution.setPenaltyPercentages(penalties, accounts, i + 1);
            vm.stopPrank();

            vm.prank(bob);
            airdropDistribution.claim(alice, true, aliceAmount, aliceProof);
            uint256 oneSixthAlice = aliceAmount / 6;
            assertApproxEqRel(
                usualToken.balanceOf(alice),
                (oneSixthAlice - oneSixthAlice.mulDiv(10, BASIS_POINT_BASE)) * (i + 1),
                1e2
            );
            vm.prank(bob);
            airdropDistribution.claim(bob, true, bobAmount, bobProof);
            uint256 oneSixthBob = bobAmount / 6;
            assertApproxEqRel(
                usualToken.balanceOf(bob),
                (oneSixthBob - oneSixthBob.mulDiv(10, BASIS_POINT_BASE)) * (i + 1),
                1e2
            );
        }

        assertApproxEqRel(
            usualToken.balanceOf(alice), aliceAmount - aliceAmount.mulDiv(10, BASIS_POINT_BASE), 1e2
        );
        assertApproxEqRel(
            usualToken.balanceOf(bob), bobAmount - bobAmount.mulDiv(10, BASIS_POINT_BASE), 1e2
        );
    }

    function testUserSkipVestingIfTaxPaid(uint256 amount) external {
        amount = bound(amount, 1, 1000 ether);
        deal(address(usd0PP), address(alice), amount);
        vm.startPrank(airdropOperator);
        address[] memory addressesToAllocateTo = new address[](1);
        addressesToAllocateTo[0] = alice;
        uint256[] memory prelaunchBalances = new uint256[](1);
        prelaunchBalances[0] = amount;
        airdropTaxCollector.setUsd0ppPrelaunchBalances(addressesToAllocateTo, prelaunchBalances);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 taxToPay = airdropTaxCollector.calculateClaimTaxAmount(alice);
        usd0PP.approve(address(airdropTaxCollector), taxToPay);
        airdropTaxCollector.payTaxAmount();
        airdropDistribution.claim(alice, true, aliceAmount, _aliceProof());

        assertEq(usualToken.balanceOf(alice), aliceAmount);
    }

    function testUserWithPenaltySkipVestingIfTaxPaid(uint256 amount) external {
        amount = bound(amount, 1 ether, 1000 ether);
        deal(address(usd0PP), address(alice), amount);
        vm.startPrank(airdropOperator);
        address[] memory addressesToAllocateTo = new address[](1);
        addressesToAllocateTo[0] = alice;
        uint256[] memory prelaunchBalances = new uint256[](1);
        prelaunchBalances[0] = amount;
        airdropTaxCollector.setUsd0ppPrelaunchBalances(addressesToAllocateTo, prelaunchBalances);
        vm.stopPrank();

        uint256 penalty = 5000; // 50%
        uint256[] memory penalties = new uint256[](1);
        penalties[0] = penalty;
        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        vm.startPrank(airdropPenaltyOperator);
        airdropDistribution.setPenaltyPercentages(penalties, accounts, 1);
        airdropDistribution.setPenaltyPercentages(penalties, accounts, 2);
        vm.stopPrank();

        vm.warp(FIRST_AIRDROP_VESTING_CLAIMING_DATE);

        vm.startPrank(alice);
        uint256 taxToPay = airdropTaxCollector.calculateClaimTaxAmount(alice);
        usd0PP.approve(address(airdropTaxCollector), taxToPay);
        airdropTaxCollector.payTaxAmount();

        airdropDistribution.claim(alice, true, aliceAmount, _aliceProof());

        uint256 oneSixthAlice = aliceAmount / 6;

        assertEq(
            usualToken.balanceOf(alice),
            aliceAmount - oneSixthAlice.mulDiv(penalty, BASIS_POINT_BASE) * 2
        );
    }

    function testPenaltyIsNotAppliedIfAccountIsNotInTop80() external {
        uint256 penaltyDavid = 10_000; // 100%

        uint256[] memory penalties = new uint256[](1);
        penalties[0] = penaltyDavid;

        address[] memory accounts = new address[](1);
        accounts[0] = david;

        bytes32[] memory davidProof = _davidProof();

        vm.prank(airdropPenaltyOperator);
        airdropDistribution.setPenaltyPercentages(penalties, accounts, 1);
        vm.stopPrank();

        vm.warp(FIRST_AIRDROP_VESTING_CLAIMING_DATE);

        vm.prank(david);
        airdropDistribution.claim(david, false, davidAmount, davidProof);
        assertEq(usualToken.balanceOf(david), davidAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        4. SET MERKLE ROOT
    //////////////////////////////////////////////////////////////*/

    // 4.1 Testing revert properties //

    function testSetMerkleRootShouldFailWhenNullRoot() external {
        vm.expectRevert(abi.encodeWithSelector(NullMerkleRoot.selector));
        vm.startPrank(airdropOperator);
        airdropDistribution.setMerkleRoot(bytes32(0));
        vm.stopPrank();
    }

    // 4.2 Testing basic flows //

    function testSetMerkleRootShouldWork() external {
        bytes32 root = 0xec468d23c3cf5371c09000d0cff5b87a7da37382679735385416be5686af734a;
        vm.startPrank(airdropOperator);
        airdropDistribution.setMerkleRoot(root);
        vm.stopPrank();
        assertEq(airdropDistribution.getMerkleRoot(), root);
    }

    function testSetMerkleRootShouldEmitEvent() external {
        bytes32 root = 0xec468d23c3cf5371c09000d0cff5b87a7da37382679735385416be5686af734a;
        vm.expectEmit();
        emit MerkleRootSet(root);
        vm.startPrank(airdropOperator);
        airdropDistribution.setMerkleRoot(root);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            5. SET PENALTY PERCENTAGE
    //////////////////////////////////////////////////////////////*/

    // 5.1 Testing revert properties //

    function testSetPenaltyPercentageShouldFailWhenPenaltyIsTooBig() external {
        uint256[] memory penalties = new uint256[](1);
        penalties[0] = BASIS_POINT_BASE + 1;

        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        vm.expectRevert(abi.encodeWithSelector(AmountTooBig.selector));
        vm.startPrank(airdropPenaltyOperator);
        airdropDistribution.setPenaltyPercentages(penalties, accounts, 1);
        vm.stopPrank();
    }

    function testSetPenaltyPercentageShouldFailWhenPenaltyIsSame() external {
        uint256[] memory penalties = new uint256[](1);
        penalties[0] = 10;

        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        vm.startPrank(airdropPenaltyOperator);
        airdropDistribution.setPenaltyPercentages(penalties, accounts, 1);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        airdropDistribution.setPenaltyPercentages(penalties, accounts, 1);
        vm.stopPrank();
    }

    function testSetPenaltyPercentageShouldFailIfMonthOutOfBounds() external {
        uint256[] memory penalties = new uint256[](1);
        penalties[0] = 10;

        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        vm.expectRevert(abi.encodeWithSelector(OutOfBounds.selector));
        vm.startPrank(airdropPenaltyOperator);
        airdropDistribution.setPenaltyPercentages(penalties, accounts, 7);
        vm.stopPrank();

        vm.warp(THIRD_AIRDROP_VESTING_CLAIMING_DATE);
        vm.expectRevert(abi.encodeWithSelector(OutOfBounds.selector));
        vm.startPrank(airdropPenaltyOperator);
        airdropDistribution.setPenaltyPercentages(penalties, accounts, 2);
        vm.stopPrank();
    }

    function testSetPenaltyPercentagesShouldFailIfOutOfBounds() external {
        uint256[] memory penalties = new uint256[](2);
        penalties[0] = 10;
        penalties[1] = 20;

        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        vm.expectRevert(abi.encodeWithSelector(InvalidInputArraysLength.selector));
        vm.startPrank(airdropPenaltyOperator);
        airdropDistribution.setPenaltyPercentages(penalties, accounts, 1);
        vm.stopPrank();
    }

    // 5.2 Testing basic flows //

    function testSetPenaltyPercentageShouldWork() external {
        uint256[] memory penalties = new uint256[](1);
        penalties[0] = 10;

        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        vm.startPrank(airdropPenaltyOperator);
        airdropDistribution.setPenaltyPercentages(penalties, accounts, 1);
        vm.stopPrank();
        assertEq(airdropDistribution.getPenaltyPercentage(alice, 1), 10);
    }

    function testSetPenaltyPercentageShouldEmitEvent() external {
        uint256[] memory penalties = new uint256[](1);
        penalties[0] = 10;

        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        vm.startPrank(airdropPenaltyOperator);
        vm.expectEmit();
        emit PenaltyPercentagesSet(accounts, penalties, 1);
        airdropDistribution.setPenaltyPercentages(penalties, accounts, 1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          6. PAUSE & UNPAUSE
    //////////////////////////////////////////////////////////////*/

    // 6.1 Testing revert properties //

    function testPauseShouldFailWhenNotAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        airdropDistribution.pause();
    }

    function testUnpauseShouldFailWhenNotAdmin() external {
        vm.expectRevert();
        airdropDistribution.unpause();
    }

    // 6.2 Testing basic flows //

    function testPauseShouldWork() external {
        vm.startPrank(pauser);
        airdropDistribution.pause();
        vm.stopPrank();
        assertTrue(airdropDistribution.paused());
    }

    function testUnpauseShouldWork() external {
        vm.prank(pauser);
        airdropDistribution.pause();
        vm.prank(admin);
        airdropDistribution.unpause();
        vm.stopPrank();
        assertFalse(airdropDistribution.paused());
    }

    /*//////////////////////////////////////////////////////////////
                            7. GETTERS
    //////////////////////////////////////////////////////////////*/

    function testGetMerkleRootShouldWork() external {
        bytes32 root = 0xec468d23c3cf5371c09000d0cff5b87a7da37382679735385416be5686af734a;
        vm.startPrank(airdropOperator);
        airdropDistribution.setMerkleRoot(root);
        vm.stopPrank();
        assertEq(airdropDistribution.getMerkleRoot(), root);
    }

    function testGetPenaltyPercentageShouldWork() external {
        uint256[] memory penalties = new uint256[](1);
        penalties[0] = 10;

        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        vm.startPrank(airdropPenaltyOperator);
        airdropDistribution.setPenaltyPercentages(penalties, accounts, 1);
        vm.stopPrank();
        assertEq(airdropDistribution.getPenaltyPercentage(alice, 1), 10);
    }

    function testGetVestingDurationShouldWork() external view {
        assertEq(airdropDistribution.getVestingDuration(), 182 days);
    }

    function testGetClaimedShouldWork() external {
        bytes32[] memory aliceProof = _aliceProof();
        skip(182 days);

        vm.prank(alice);
        airdropDistribution.claim(alice, true, aliceAmount, aliceProof);
        assertEq(airdropDistribution.getClaimed(alice), aliceAmount);
    }

    /*//////////////////////////////////////////////////////////////
                          8. Early Unlock
    //////////////////////////////////////////////////////////////*/

    // 8.1 Testing revert properties //

    function testVoidAnyOutstandingAirdropShouldFailWhenNotUsd0PP() external {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        airdropDistribution.voidAnyOutstandingAirdrop(alice);
    }

    // 8.2 Basic Flows //

    function _createRwa() internal {
        vm.prank(admin);
        address rwa = rwaFactory.createRwa("rwa", "rwa", 6);
        whitelistPublisher(address(rwa), address(stbcToken));

        _setupBucket(address(rwa), address(stbcToken));

        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1.1e18);
        treasury = address(registryContract.getContract(CONTRACT_TREASURY));

        vm.mockCall(
            address(classicalOracle),
            abi.encodeWithSelector(IOracle.getPrice.selector, rwa),
            abi.encode(1e6)
        );

        deal(rwa, treasury, type(uint128).max);
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);
    }

    function testClaimInitialShouldNotWorkIfEarlyUnlocked() external {
        // setup
        bytes32[] memory aliceProof = _aliceProof();
        _createRwa();
        Usd0PP usd0PP100 = _createBond("UsualDAO Bond 100", "USD0PP A100");
        uint256 amount = 9000 * 1e18 + 1; // It's over 9000!
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        uint256 earlyUnlockStart = block.timestamp - 1;
        uint256 earlyUnlockStop = END_OF_EARLY_UNLOCK_PERIOD - 1;
        vm.startPrank(admin);
        registryAccess.grantRole(EARLY_BOND_UNLOCK_ROLE, admin);
        usd0PP100.setupEarlyUnlockPeriod(earlyUnlockStart, earlyUnlockStop);
        uint256[] memory redemptionAmountsToAllocate = new uint256[](1);
        address[] memory redemptionAddressesToAllocateTo = new address[](1);
        redemptionAmountsToAllocate[0] = amount;
        redemptionAddressesToAllocateTo[0] = address(alice);
        usd0PP100.allocateEarlyUnlockBalance(
            redemptionAddressesToAllocateTo, redemptionAmountsToAllocate
        );
        vm.stopPrank();

        // tested logic
        vm.startPrank(address(alice));
        stbcToken.approve(address(usd0PP100), amount);
        usd0PP100.mint(amount);
        usd0PP100.temporaryOneToOneExitUnwrap(amount);
        vm.stopPrank();

        // assertions
        vm.expectRevert(abi.encodeWithSelector(AirdropVoided.selector));
        airdropDistribution.claim(alice, true, aliceAmount, aliceProof);

        vm.startPrank(address(usd0PP100));
        vm.expectRevert(abi.encodeWithSelector(AirdropVoided.selector));
        airdropDistribution.voidAnyOutstandingAirdrop(alice);
        vm.stopPrank();
    }
}
