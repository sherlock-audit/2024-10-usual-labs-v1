// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";

import {IAirdropTaxCollector} from "src/interfaces/airdrop/IAirdropTaxCollector.sol";
import {AirdropTaxCollector} from "src/airdrop/AirdropTaxCollector.sol";

import {SetupTest} from "../setup.t.sol";

import {
    AIRDROP_INITIAL_START_TIME,
    AIRDROP_CLAIMING_PERIOD_LENGTH,
    BASIS_POINT_BASE,
    PAUSING_CONTRACTS_ROLE,
    EARLY_BOND_UNLOCK_ROLE,
    DEFAULT_ADMIN_ROLE
} from "src/constants.sol";

import {
    ClaimerHasPaidTax,
    SameValue,
    NullContract,
    NotAuthorized,
    InvalidMaxChargeableTax,
    NotInClaimingPeriod,
    InvalidInputArraysLength,
    InvalidClaimingPeriodStartDate,
    AirdropVoided
} from "src/errors.sol";

contract AirdropTaxCollectorTest is SetupTest {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                                1. SETUP & HELPERS
    //////////////////////////////////////////////////////////////*/

    uint256 constant TEN_PERCENT = 1000;

    event AirdropTaxPaid(address indexed account, uint256 claimTaxAmount);

    modifier contractPaused() {
        vm.prank(pauser);
        airdropTaxCollector.pause();
        _;
    }

    modifier calledByAirdropOperator() {
        vm.startPrank(airdropOperator);
        _;
        vm.stopPrank();
    }

    modifier calledByPausingContractsRole() {
        vm.startPrank(pauser);
        _;
        vm.stopPrank();
    }

    modifier calledByDefaultAdminRole() {
        vm.startPrank(admin);
        _;
        vm.stopPrank();
    }

    modifier withMaxChargeableTax(uint256 _maxChargeableTax) {
        vm.prank(airdropOperator);
        airdropTaxCollector.setMaxChargeableTax(_maxChargeableTax);
        _;
    }

    modifier afterClaimingPeriodStart(uint256 _time) {
        skip(AIRDROP_INITIAL_START_TIME + _time);
        _;
    }

    modifier userPaidTax(address _claimer) {
        vm.startPrank(_claimer);
        airdropTaxCollector.payTaxAmount();
        vm.stopPrank();
        _;
    }

    modifier userOwnsUSD0PP(address _claimer, uint256 _amount) {
        deal(address(usd0PP), _claimer, _amount);
        _;
    }

    modifier userApprovedUSD0PPToAirdropTaxCollector(address _claimer) {
        vm.prank(_claimer);
        usd0PP.approve(address(airdropTaxCollector), type(uint256).max);
        _;
    }

    modifier userHasPrelaunchBalance(address _claimer, uint256 _amount) {
        vm.startPrank(airdropOperator);
        address[] memory addressesToAllocateTo = new address[](1);
        addressesToAllocateTo[0] = _claimer;
        uint256[] memory prelaunchBalances = new uint256[](1);
        prelaunchBalances[0] = _amount;
        airdropTaxCollector.setUsd0ppPrelaunchBalances(addressesToAllocateTo, prelaunchBalances);
        vm.stopPrank();
        _;
    }

    modifier fuzzTestsAssume(uint256 _claimerBalance) {
        vm.assume(_claimerBalance > 100);
        _;
    }

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                                2. INITIALIZER
    //////////////////////////////////////////////////////////////*/

    // 2.1 Testing revert properties //
    function testInitializerShouldFailWhenNullContract() external {
        _resetInitializerImplementation(address(airdropTaxCollector));
        vm.expectRevert(abi.encodeWithSelector(NullContract.selector));
        airdropTaxCollector.initialize(address(0));
    }

    function testInitializerShouldFailWhenAirdropStartDateIsInThePast() external {
        _resetInitializerImplementation(address(airdropTaxCollector));
        vm.warp(AIRDROP_INITIAL_START_TIME + 1);
        vm.expectRevert(abi.encodeWithSelector(InvalidClaimingPeriodStartDate.selector));
        airdropTaxCollector.initialize(address(registryContract));
    }

    // 2.2 Testing basic flows //
    function testInitializeShouldWork() external {
        _resetInitializerImplementation(address(airdropTaxCollector));
        vm.startPrank(admin);
        airdropTaxCollector.initialize(address(registryContract));
        vm.stopPrank();

        (uint256 startDate, uint256 endDate) = airdropTaxCollector.getClaimingPeriod();
        assertEq(startDate, AIRDROP_INITIAL_START_TIME);
        assertEq(endDate, AIRDROP_INITIAL_START_TIME + AIRDROP_CLAIMING_PERIOD_LENGTH);
    }

    function testConstructorShouldWork() external {
        IAirdropTaxCollector taxCollector = new AirdropTaxCollector();
        assertTrue(address(taxCollector) != address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        3. RESTRICTED OPERATIONS
    //////////////////////////////////////////////////////////////*/

    // 3.1 Setting Max Chargeable Tax //
    function testSetMaxChargeableTaxShouldWork() external calledByAirdropOperator {
        uint256 onePercent = 100;

        airdropTaxCollector.setMaxChargeableTax(onePercent);
        assertEq(airdropTaxCollector.getMaxChargeableTax(), onePercent);
    }

    function testSetMaxChargeableTaxShouldFailWhenAmountIsZero() external calledByAirdropOperator {
        uint256 zero = 0;

        vm.expectRevert(abi.encodeWithSelector(InvalidMaxChargeableTax.selector));
        airdropTaxCollector.setMaxChargeableTax(zero);
    }

    function testSetMaxChargeableTaxShouldFailWhenAmountIsGreaterThanBasisPointBase()
        external
        calledByAirdropOperator
    {
        uint256 greaterThanBasisPointBase = BASIS_POINT_BASE + 1;

        vm.expectRevert(abi.encodeWithSelector(InvalidMaxChargeableTax.selector));
        airdropTaxCollector.setMaxChargeableTax(greaterThanBasisPointBase);
    }

    function testSetMaxChargeableTaxShouldFailWhenAmountIsSameValueAsBefore()
        external
        calledByAirdropOperator
    {
        uint256 onePercent = 100;

        airdropTaxCollector.setMaxChargeableTax(onePercent);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        airdropTaxCollector.setMaxChargeableTax(onePercent);
    }

    function testSetMaxChargeableTaxShouldFailWhenNotCalledByAirdropOperatorRole() external {
        uint256 onePercent = 100;

        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        airdropTaxCollector.setMaxChargeableTax(onePercent);
    }

    // 3.2 Pausing and Unpausing //

    function testPauseShouldWork() external calledByPausingContractsRole {
        airdropTaxCollector.pause();
        assertTrue(airdropTaxCollector.paused());
    }

    function testPauseShouldFailWhenNotCalledByPausingContractsRole(address caller) external {
        vm.assume(caller != pauser);

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        airdropTaxCollector.pause();
    }

    function testUnpauseShouldWorkWhenCalledByDefaultAdmin()
        external
        contractPaused
        calledByDefaultAdminRole
    {
        airdropTaxCollector.unpause();
        assertFalse(airdropTaxCollector.paused());
    }

    function testUnpauseShouldFailWhenNotCalledByAdmin(address caller) external contractPaused {
        vm.assume(caller != admin);

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        airdropTaxCollector.unpause();
    }

    function testUnpauseShouldFailWhenCalledByAirdropOperator() external contractPaused {
        vm.startPrank(airdropOperator);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        airdropTaxCollector.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                        4. VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // 4.1 hasPaidTax //
    function testHasPaidTaxShouldReturnFalseWhenClaimerHasNotPaidTax() external view {
        assertFalse(airdropTaxCollector.hasPaidTax(alice));
    }

    function testHasPaidTaxShouldReturnTrueWhenClaimerHasPaidTax()
        external
        withMaxChargeableTax(TEN_PERCENT)
        userOwnsUSD0PP(alice, 1000 ether)
        userHasPrelaunchBalance(alice, 1000 ether)
        afterClaimingPeriodStart(0 days)
        userApprovedUSD0PPToAirdropTaxCollector(alice)
        userPaidTax(alice)
    {
        assertTrue(airdropTaxCollector.hasPaidTax(alice));
    }

    // 4.2 calculateClaimTaxAmount //
    function testCalculateClaimTaxAmountShouldWork()
        external
        withMaxChargeableTax(TEN_PERCENT)
        userHasPrelaunchBalance(alice, 1000 ether)
        afterClaimingPeriodStart(0 days)
    {
        vm.warp(AIRDROP_INITIAL_START_TIME);
        uint256 expectedTaxAmount = 100 ether;
        uint256 taxAmount = airdropTaxCollector.calculateClaimTaxAmount(alice);

        assertEq(taxAmount, expectedTaxAmount);
    }

    function testCalculateClaimTaxAmountShouldReturnLowerValueOverTime()
        external
        withMaxChargeableTax(TEN_PERCENT)
        userHasPrelaunchBalance(alice, 1000 ether)
        afterClaimingPeriodStart(0)
    {
        uint256 previousTaxAmount = airdropTaxCollector.calculateClaimTaxAmount(alice);

        while (block.timestamp < AIRDROP_INITIAL_START_TIME + AIRDROP_CLAIMING_PERIOD_LENGTH) {
            skip(1 days);
            uint256 taxAmount = airdropTaxCollector.calculateClaimTaxAmount(alice);

            assertTrue(taxAmount < previousTaxAmount);
            previousTaxAmount = taxAmount;
        }
    }

    function testCalculateClaimTaxAmountShouldOnlyCalculateBasedOnPrelaunchAmount()
        external
        withMaxChargeableTax(TEN_PERCENT)
        userHasPrelaunchBalance(alice, 1000 ether)
        userOwnsUSD0PP(alice, 1000 ether)
    {
        vm.warp(AIRDROP_INITIAL_START_TIME);
        uint256 taxAmount = airdropTaxCollector.calculateClaimTaxAmount(alice);

        deal(address(usd0PP), alice, usd0PP.balanceOf(alice) * 2);

        vm.warp(AIRDROP_INITIAL_START_TIME);
        uint256 taxAmountAfterBalanceChange = airdropTaxCollector.calculateClaimTaxAmount(alice);

        assertEq(taxAmount, taxAmountAfterBalanceChange);
    }

    function testFuzzCalculateTaxAmount(uint256 _claimerBalance)
        external
        fuzzTestsAssume(_claimerBalance)
        withMaxChargeableTax(TEN_PERCENT)
        userHasPrelaunchBalance(alice, _claimerBalance)
    {
        vm.warp(AIRDROP_INITIAL_START_TIME);
        uint256 taxAmount = airdropTaxCollector.calculateClaimTaxAmount(alice);

        vm.warp(AIRDROP_INITIAL_START_TIME + (AIRDROP_CLAIMING_PERIOD_LENGTH / 2));
        uint256 taxAmountAfterHalfClaimingPeriod =
            airdropTaxCollector.calculateClaimTaxAmount(alice);

        vm.warp(AIRDROP_INITIAL_START_TIME + AIRDROP_CLAIMING_PERIOD_LENGTH);
        uint256 taxAmountAfterClaimingPeriod = airdropTaxCollector.calculateClaimTaxAmount(alice);

        assertTrue(taxAmount > taxAmountAfterHalfClaimingPeriod);
        assertTrue(taxAmount / taxAmountAfterHalfClaimingPeriod == 2);
        assertTrue(taxAmountAfterHalfClaimingPeriod > taxAmountAfterClaimingPeriod);
    }

    function testCalculateClaimTaxShouldReturnZeroWhenClaimingPeriodIsOver()
        external
        withMaxChargeableTax(TEN_PERCENT)
        userHasPrelaunchBalance(alice, 1000 ether)
        afterClaimingPeriodStart(AIRDROP_CLAIMING_PERIOD_LENGTH)
    {
        uint256 taxAmount = airdropTaxCollector.calculateClaimTaxAmount(alice);
        assertEq(taxAmount, 0);
    }

    // 4.3 getClaimingPeriod //
    function testGetClaimingPeriodShouldWork() external view {
        (uint256 startDate, uint256 endDate) = airdropTaxCollector.getClaimingPeriod();
        assertEq(startDate, AIRDROP_INITIAL_START_TIME);
        assertEq(endDate, AIRDROP_INITIAL_START_TIME + AIRDROP_CLAIMING_PERIOD_LENGTH);
    }

    // 4.4 getMaxChargeableTax //
    function testGetMaxChargeableTaxShouldWork() external view {
        uint256 oneHundredPercent = BASIS_POINT_BASE;
        assertEq(airdropTaxCollector.getMaxChargeableTax(), oneHundredPercent);
    }

    function testGetMaxChargeableTaxShouldReturnSetAmount() external withMaxChargeableTax(500) {
        assertEq(airdropTaxCollector.getMaxChargeableTax(), 500);
    }

    /*//////////////////////////////////////////////////////////////
                        5. PAYING AIRDROP TAX
    //////////////////////////////////////////////////////////////*/

    // 5.1 payTaxAmount //
    function testPayTaxAmountShouldWork()
        external
        withMaxChargeableTax(TEN_PERCENT)
        userHasPrelaunchBalance(alice, 1000 ether)
        userOwnsUSD0PP(alice, 1000 ether)
        afterClaimingPeriodStart(0 days)
        userApprovedUSD0PPToAirdropTaxCollector(alice)
    {
        assertFalse(airdropTaxCollector.hasPaidTax(alice));

        vm.prank(alice);
        airdropTaxCollector.payTaxAmount();

        assertTrue(airdropTaxCollector.hasPaidTax(alice));
    }

    function testPayTaxAmountShouldTransferUsd00ppToTreasury()
        external
        withMaxChargeableTax(TEN_PERCENT)
        userHasPrelaunchBalance(alice, 1000 ether)
        userOwnsUSD0PP(alice, 1000 ether)
        afterClaimingPeriodStart(0 days)
        userApprovedUSD0PPToAirdropTaxCollector(alice)
    {
        uint256 treasuryBalanceBefore = usd0PP.balanceOf(treasury);
        uint256 aliceBalanceBefore = usd0PP.balanceOf(alice);

        vm.prank(alice);
        airdropTaxCollector.payTaxAmount();

        uint256 treasuryBalanceAfter = usd0PP.balanceOf(treasury);
        uint256 aliceBalanceAfter = usd0PP.balanceOf(alice);

        assertTrue(treasuryBalanceAfter > treasuryBalanceBefore);
        assertTrue(aliceBalanceAfter < aliceBalanceBefore);
        assertEq(
            treasuryBalanceBefore + aliceBalanceBefore, treasuryBalanceAfter + aliceBalanceAfter
        );
    }

    function testPayTaxAmountShouldRaiseEvent()
        external
        withMaxChargeableTax(TEN_PERCENT)
        userHasPrelaunchBalance(alice, 1000 ether)
        userOwnsUSD0PP(alice, 1000 ether)
        afterClaimingPeriodStart(0 days)
        userApprovedUSD0PPToAirdropTaxCollector(alice)
    {
        uint256 taxAmount = airdropTaxCollector.calculateClaimTaxAmount(alice);

        vm.expectEmit(true, true, true, true, address(airdropTaxCollector));
        emit AirdropTaxPaid(alice, taxAmount);

        vm.prank(alice);
        airdropTaxCollector.payTaxAmount();
    }

    function testPayTaxAmountShouldFailWhenClaimerHasNotApprovedUSD0PPToAirdropTaxCollector()
        external
        withMaxChargeableTax(TEN_PERCENT)
        userHasPrelaunchBalance(alice, 1000 ether)
        userOwnsUSD0PP(alice, 1000 ether)
        afterClaimingPeriodStart(0 days)
    {
        uint256 taxAmount = airdropTaxCollector.calculateClaimTaxAmount(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, airdropTaxCollector, 0, taxAmount
            )
        );

        vm.prank(alice);
        airdropTaxCollector.payTaxAmount();
    }

    function testPayTaxAmountShouldFailWhenClaimerHasAlreadyPaidTax()
        external
        withMaxChargeableTax(TEN_PERCENT)
        userHasPrelaunchBalance(alice, 1000 ether)
        userOwnsUSD0PP(alice, 1000 ether)
        afterClaimingPeriodStart(0 days)
        userApprovedUSD0PPToAirdropTaxCollector(alice)
        userPaidTax(alice)
    {
        vm.expectRevert(abi.encodeWithSelector(ClaimerHasPaidTax.selector));
        vm.prank(alice);
        airdropTaxCollector.payTaxAmount();
    }

    function testPayTaxAmountShouldFailWhenEarlyUnlockedAirdrop()
        external
        withMaxChargeableTax(TEN_PERCENT)
        userHasPrelaunchBalance(alice, 1000 ether)
        userOwnsUSD0PP(alice, 1000 ether)
        afterClaimingPeriodStart(0 days)
        userApprovedUSD0PPToAirdropTaxCollector(alice)
    {
        deal(address(stbcToken), address(usd0PP), 1000 ether);
        uint256[] memory redemptionAmountsToAllocate = new uint256[](1);
        address[] memory redemptionAddressesToAllocateTo = new address[](1);
        redemptionAmountsToAllocate[0] = 1000 ether;
        redemptionAddressesToAllocateTo[0] = alice;
        vm.startPrank(admin);
        registryAccess.grantRole(EARLY_BOND_UNLOCK_ROLE, admin);
        usd0PP.allocateEarlyUnlockBalance(
            redemptionAddressesToAllocateTo, redemptionAmountsToAllocate
        );
        usd0PP.setupEarlyUnlockPeriod(block.timestamp - 1, block.timestamp + 1);
        vm.stopPrank();

        vm.startPrank(alice);
        usd0PP.temporaryOneToOneExitUnwrap(1000 ether);
        vm.expectRevert(abi.encodeWithSelector(AirdropVoided.selector));
        airdropTaxCollector.payTaxAmount();
    }

    function testPayTaxAmountShouldFailWhenClaimingPeriodIsOver()
        external
        withMaxChargeableTax(TEN_PERCENT)
        userHasPrelaunchBalance(alice, 1000 ether)
        userOwnsUSD0PP(alice, 1000 ether)
        afterClaimingPeriodStart(182 days)
        userApprovedUSD0PPToAirdropTaxCollector(alice)
    {
        vm.expectRevert(abi.encodeWithSelector(NotInClaimingPeriod.selector));
        vm.prank(alice);
        airdropTaxCollector.payTaxAmount();
    }

    /*//////////////////////////////////////////////////////////////
                        6. SETTING PRELAUNCH BALANCES
    //////////////////////////////////////////////////////////////*/

    // 6.1 Testing setUsd0ppPrelaunchBalances //

    function testSetUsd0ppPrelaunchBalancesShouldWork()
        external
        afterClaimingPeriodStart(0 days)
        calledByAirdropOperator
    {
        address[] memory addressesToAllocateTo = new address[](2);
        addressesToAllocateTo[0] = alice;
        addressesToAllocateTo[1] = bob;
        uint256[] memory balancesToAllocateTo = new uint256[](2);
        balancesToAllocateTo[0] = 1000 ether;
        balancesToAllocateTo[1] = 2000 ether;
        airdropTaxCollector.setUsd0ppPrelaunchBalances(addressesToAllocateTo, balancesToAllocateTo);
        airdropTaxCollector.setMaxChargeableTax(TEN_PERCENT);
        vm.warp(AIRDROP_INITIAL_START_TIME);
        uint256 taxAlice = airdropTaxCollector.calculateClaimTaxAmount(alice);
        uint256 taxBob = airdropTaxCollector.calculateClaimTaxAmount(bob);

        uint256 expectedTaxAlice = balancesToAllocateTo[0].mulDiv(TEN_PERCENT, BASIS_POINT_BASE); // 10% of 1000 ether
        uint256 expectedTaxBob = balancesToAllocateTo[1].mulDiv(TEN_PERCENT, BASIS_POINT_BASE); // 10% of 2000 ether

        assertEq(taxAlice, expectedTaxAlice);
        assertEq(taxBob, expectedTaxBob);
    }

    function testSetUsd0ppPrelaunchBalancesShouldFailWhenNotCalledByAirdropOperator() external {
        address[] memory addressesToAllocateTo = new address[](1);
        addressesToAllocateTo[0] = alice;
        uint256[] memory balancesToAllocateTo = new uint256[](1);
        balancesToAllocateTo[0] = 1000 ether;

        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        airdropTaxCollector.setUsd0ppPrelaunchBalances(addressesToAllocateTo, balancesToAllocateTo);
    }

    function testSetUsd0ppPrelaunchBalancesShouldFailWhenArraysHaveDifferentLengths()
        external
        calledByAirdropOperator
    {
        address[] memory addressesToAllocateTo = new address[](2);
        addressesToAllocateTo[0] = alice;
        addressesToAllocateTo[1] = bob;
        uint256[] memory balancesToAllocateTo = new uint256[](1);
        balancesToAllocateTo[0] = 1000 ether;

        vm.expectRevert(abi.encodeWithSelector(InvalidInputArraysLength.selector));
        airdropTaxCollector.setUsd0ppPrelaunchBalances(addressesToAllocateTo, balancesToAllocateTo);
    }

    function testSetUsd0ppPrelaunchBalancesShouldFailWhenAmountIsZero()
        external
        calledByAirdropOperator
    {
        address[] memory addressesToAllocateTo = new address[](1);
        addressesToAllocateTo[0] = alice;
        uint256[] memory balancesToAllocateTo = new uint256[](1);
        balancesToAllocateTo[0] = 0;

        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        airdropTaxCollector.setUsd0ppPrelaunchBalances(addressesToAllocateTo, balancesToAllocateTo);
    }
}
