// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {MyERC20} from "src/mock/myERC20.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import {SetupTest} from "test/setup.t.sol";
import {MockAggregator} from "src/mock/MockAggregator.sol";
import {LUsd0PP} from "src/workInProgress/LUsd0PP.sol";
import {Usd0PP} from "src/token/Usd0PP.sol";
import {IAggregator} from "src/interfaces/oracles/IAggregator.sol";
import {IOracle} from "src/interfaces/oracles/IOracle.sol";
import {
    CONTRACT_USD0PP,
    USD0_MINT,
    CONTRACT_TREASURY,
    BOND_DURATION_FOUR_YEAR,
    PEG_MAINTAINER_ROLE,
    USYC
} from "src/constants.sol";
import {NotOwner, NotClaimableYet, AlreadyClaimed, InvalidOrderId} from "src/errors.sol";

import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";

contract LUsd0PPTest is SetupTest {
    address public rwa;
    MockAggregator public yieldOracle;
    LUsd0PP public lusd0PP;

    event Deposit(address indexed account, uint256 indexed depositID, uint256 amount);
    event Withdraw(
        address indexed owner,
        uint256 indexed depositID,
        uint256 amount,
        uint256 roundId,
        bool usualRewards
    );
    event ExitEarly(address indexed owner, uint256 indexed depositId, uint256 amount);

    function setUp() public virtual override {
        super.setUp();
        _createRwa();
        vm.prank(hashnote);
        dataPublisher.publishData(address(rwa), 1e6);
        usd0PP = _createBond("UsualDAO Bond 100", "USD0PP A100");
        // yieldOracle is a mock IAggregator
        MyERC20 token = new MyERC20("YIELD", "YIELD", 7);
        // advance 1 day
        skip(1 days);
        // 1e7 means 1% interest rate
        yieldOracle = new MockAggregator(address(token), 1e7, 1);
        // advance 1 day
        skip(2 days);
        yieldOracle.pushData(1e7, 2);
        //amount = Normalize.tokenAmountToWad(amount, uint8(dataSource.decimals()));
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = yieldOracle.latestRoundData();
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(roundId, 1);
        assertEq(answeredInRound, 2);
        assertEq(answer, 1e7);
    }

    function testUnpause() public {
        testAnyoneCanCreateLUsd0PP();
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        lusd0PP.pause();

        vm.prank(pauser);
        lusd0PP.pause();

        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        lusd0PP.unpause();

        vm.prank(admin);
        lusd0PP.unpause();
    }

    function testAnyoneCanCreateLUsd0PP() public {
        lusd0PP = new LUsd0PP();
        _resetInitializerImplementation(address(lusd0PP));
        lusd0PP.initialize(address(registryContract), address(yieldOracle));
    }

    function testNewLUsd0PPShouldFailIfWrongParameters() public {
        LUsd0PP lusd0PPTmp = new LUsd0PP();
        _resetInitializerImplementation(address(lusd0PPTmp));

        vm.expectRevert(abi.encodeWithSelector(NullContract.selector));
        lusd0PPTmp.initialize(address(0), address(0));

        lusd0PPTmp = new LUsd0PP();
        _resetInitializerImplementation(address(lusd0PPTmp));

        vm.expectRevert(abi.encodeWithSelector(NullContract.selector));
        lusd0PPTmp.initialize(address(registryContract), address(0));
    }

    function _createRwa() internal {
        vm.prank(admin);
        rwa = rwaFactory.createRwa("rwa", "rwa", 6);
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
    }

    function testDeposit(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        testAnyoneCanCreateLUsd0PP();
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        vm.startPrank(address(alice));
        // swap for USD0
        // approve USD0 to daoCollateral
        stbcToken.approve(address(usd0PP), amount);
        usd0PP.mint(amount);
        usd0PP.approve(address(lusd0PP), amount);
        assertEq(usd0PP.balanceOf(address(alice)), amount);
        vm.expectEmit(true, true, true, true);
        emit Deposit(alice, 1, amount);
        uint256 depositID = lusd0PP.deposit(amount);
        vm.stopPrank();
        assertEq(usd0PP.balanceOf(address(alice)), 0);
        assertEq(depositID, 1);
        (address owner, uint256 amountDeposited, uint256 timestamp, bool usualRewards) =
            lusd0PP.getDeposit(1);
        assertEq(owner, address(alice));
        assertEq(amountDeposited, amount);
        assertEq(timestamp, block.timestamp);
        assertEq(usualRewards, false);
    }

    function testDepositWithDepositFailIfSigIncorrect() public {
        uint256 amount = 100e18;
        testAnyoneCanCreateLUsd0PP();
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        vm.startPrank(address(alice));
        // swap for USD0
        // approve USD0 to daoCollateral
        stbcToken.approve(address(usd0PP), amount);
        usd0PP.mint(amount);
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(usd0PP), alice, bobPrivKey, address(lusd0PP), amount, deadline
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(lusd0PP), 0, amount
            )
        );
        lusd0PP.depositWithPermit(amount, deadline, v, r, s);
        vm.stopPrank();
    }

    function testDepositWithPermit(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        testAnyoneCanCreateLUsd0PP();
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount);
        vm.startPrank(address(alice));
        // swap for USD0
        // approve USD0 to daoCollateral
        stbcToken.approve(address(usd0PP), amount);
        usd0PP.mint(amount);
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(usd0PP), alice, alicePrivKey, address(lusd0PP), amount, deadline
        );
        uint256 depositID = lusd0PP.depositWithPermit(amount, deadline, v, r, s);
        vm.stopPrank();
        assertEq(depositID, 1);
        (address owner, uint256 amountDeposited, uint256 timestamp, bool usualRewards) =
            lusd0PP.getDeposit(1);
        assertEq(owner, address(alice));
        assertEq(amountDeposited, amount);
        assertEq(timestamp, block.timestamp);
        assertEq(usualRewards, false);
    }

    function testWithdrawUsd0ShouldWork(uint256 amount) public {
        amount = bound(amount, 100, type(uint64).max);

        testDeposit(amount);
        assertEq(stbcToken.balanceOf(address(alice)), 0);
        // lusd0pp must have the USD0_MINT role
        vm.prank(admin);
        registryAccess.grantRole(USD0_MINT, address(lusd0PP));
        // deposit 1 should exist
        (address owner, uint256 amountDeposited, uint256 timestamp, bool usualRewards) =
            lusd0PP.getDeposit(1);
        assertEq(owner, address(alice));
        assertEq(amountDeposited, amount);
        assertEq(timestamp, block.timestamp);
        assertEq(usualRewards, false);
        // move 180days in the future
        skip(180 days);
        yieldOracle.pushData(1e7, 3);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(alice, 1, amount, 2, false);
        vm.prank(alice);
        lusd0PP.withdraw(1, 2, false);
        assertEq(usd0PP.balanceOf(address(alice)), amount);
        // rewards should be  1% of the amount approximately equal with delta percentage of 0.0001%
        assertApproxEqRel(stbcToken.balanceOf(address(alice)), amount / 100, 0.00001e18);

        // deposit 1 should not exist anymore
        (owner, amountDeposited, timestamp, usualRewards) = lusd0PP.getDeposit(1);
        assertEq(owner, address(0));
        assertEq(amountDeposited, 0);
        assertEq(timestamp, 0);
        assertEq(usualRewards, false);
    }

    function testWithdrawUsd0RewardsHigherThanDepositFail() public {
        uint256 amount = 1_000_000 ether;

        testDeposit(amount);
        assertEq(stbcToken.balanceOf(address(alice)), 0);
        // lusd0pp must have the USD0_MINT role
        vm.prank(admin);
        registryAccess.grantRole(USD0_MINT, address(lusd0PP));
        // deposit 1 should exist
        (address owner, uint256 amountDeposited, uint256 timestamp, bool usualRewards) =
            lusd0PP.getDeposit(1);
        assertEq(owner, address(alice));
        assertEq(amountDeposited, amount);
        assertEq(timestamp, block.timestamp);
        assertEq(usualRewards, false);
        // move 180days in the future
        skip(180 days);
        yieldOracle.pushData(101e7, 3);
        // expect a revert because of the rewards being higher than the deposit
        vm.expectRevert();
        vm.prank(alice);
        lusd0PP.withdraw(1, 2, false);
    }

    function testWithdrawUsd0AlreadyClaimedFail() public {
        uint256 amount = 100 ether;
        testWithdrawUsd0ShouldWork(amount);
        // expect revert NotOwner because the deposit was already claimed and deleted
        vm.expectRevert(abi.encodeWithSelector(NotOwner.selector));
        vm.prank(alice);
        lusd0PP.withdraw(1, 2, false);
    }

    function testWithdrawAfterTwoDepositsShouldWork(uint256 amount) public {
        amount = bound(amount, 100, type(uint128).max - 1000e18);

        testDeposit(amount);

        // lusd0pp must have the USD0_MINT role
        vm.prank(admin);
        registryAccess.grantRole(USD0_MINT, address(lusd0PP));
        // deposit 1 should exist
        (address owner, uint256 amountDeposited, uint256 timestamp, bool usualRewards) =
            lusd0PP.getDeposit(1);
        assertEq(owner, address(alice));
        assertEq(amountDeposited, amount);
        assertEq(timestamp, block.timestamp);
        assertEq(usualRewards, false);
        skip(90 days);

        uint256 amount2 = 1000e18;
        vm.prank(address(daoCollateral));
        stbcToken.mint(address(alice), amount2);
        vm.startPrank(address(alice));
        // swap for USD0
        // approve USD0 to daoCollateral
        stbcToken.approve(address(usd0PP), amount2);
        usd0PP.mint(amount2);
        usd0PP.approve(address(lusd0PP), amount2);
        assertEq(usd0PP.balanceOf(address(alice)), amount2);
        vm.expectEmit(true, true, true, true);
        emit Deposit(alice, 2, amount2);
        uint256 depositID = lusd0PP.deposit(amount2);
        vm.stopPrank();
        assertEq(usd0PP.balanceOf(address(alice)), 0);
        assertEq(depositID, 2);
        (owner, amountDeposited, timestamp, usualRewards) = lusd0PP.getDeposit(2);
        assertEq(owner, address(alice));
        assertEq(amountDeposited, amount2);
        assertEq(timestamp, block.timestamp);
        assertEq(usualRewards, false);

        assertEq(stbcToken.balanceOf(address(alice)), 0);
        skip(90 days);
        // push RWA price
        vm.mockCall(
            address(classicalOracle),
            abi.encodeWithSelector(IOracle.getPrice.selector, rwa),
            abi.encode(1.1e6)
        );

        yieldOracle.pushData(1e7, 3);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(alice, 1, amount, 2, false);
        vm.prank(alice);
        lusd0PP.withdraw(1, 2, false);
        assertEq(usd0PP.balanceOf(address(alice)), amount);
        // rewards should be  1% of the amount approximately equal with delta percentage of 0.0001%
        assertApproxEqRel(stbcToken.balanceOf(address(alice)), amount / 100, 0.00001e18);
        uint256 curUsd0Balance = stbcToken.balanceOf(address(alice));
        // deposit 1 should not exist anymore
        (owner, amountDeposited, timestamp, usualRewards) = lusd0PP.getDeposit(1);
        assertEq(owner, address(0));
        assertEq(amountDeposited, 0);
        assertEq(timestamp, 0);
        assertEq(usualRewards, false);
        // can't claim second deposit yet
        vm.expectRevert(abi.encodeWithSelector(NotClaimableYet.selector));
        vm.prank(alice);
        lusd0PP.withdraw(2, 3, false);
        // move 90 days in the future
        skip(90 days);
        yieldOracle.pushData(2e7, 4);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(alice, 2, amount2, 3, false);
        vm.prank(alice);
        lusd0PP.withdraw(2, 3, false);
        assertEq(usd0PP.balanceOf(address(alice)), amount + amount2);
        // rewards should be  2% of the amount2 approximately equal with delta percentage of 0.0001%
        uint256 secondDepositRewards = stbcToken.balanceOf(address(alice)) - curUsd0Balance;
        assertApproxEqRel(secondDepositRewards, (amount2 / 100) * 2, 0.00001e18);
    }

    function testWithdrawUsd0FailIfNotOwner() public {
        uint256 amount = 1000e18;

        testDeposit(amount);
        assertEq(stbcToken.balanceOf(address(alice)), 0);
        // lusd0pp must have the USD0_MINT role
        vm.prank(admin);
        registryAccess.grantRole(USD0_MINT, address(lusd0PP));
        // move 180days in the future
        skip(180 days);
        yieldOracle.pushData(1e7, 3);
        vm.expectRevert(abi.encodeWithSelector(NotOwner.selector));
        vm.prank(bob);
        lusd0PP.withdraw(1, 2, false);
    }

    function testWithdrawUsd0FailIfNotClaimableYet() public {
        uint256 amount = 1000e18;

        testDeposit(amount);
        assertEq(stbcToken.balanceOf(address(alice)), 0);
        // lusd0pp must have the USD0_MINT role
        vm.prank(admin);
        registryAccess.grantRole(USD0_MINT, address(lusd0PP));
        // move 180days in the future
        skip(180 days - 1);
        yieldOracle.pushData(1e7, 3);
        vm.expectRevert(abi.encodeWithSelector(NotClaimableYet.selector));
        vm.prank(alice);
        lusd0PP.withdraw(1, 2, false);
    }

    function testWithdrawUsualShouldWork(uint256 amount) public {
        amount = bound(amount, 100, type(uint64).max);

        testDeposit(amount);
        assertEq(stbcToken.balanceOf(address(alice)), 0);
        // lusd0pp must have the USD0_MINT role
        vm.prank(admin);
        registryAccess.grantRole(USD0_MINT, address(lusd0PP));
        // deposit 1 should exist
        (address owner, uint256 amountDeposited, uint256 timestamp, bool usualRewards) =
            lusd0PP.getDeposit(1);
        uint256 currentTimestamp = block.timestamp;
        assertEq(owner, address(alice));
        assertEq(amountDeposited, amount);
        assertEq(timestamp, currentTimestamp);
        assertEq(usualRewards, false);
        // move 180days in the future
        skip(180 days);
        yieldOracle.pushData(1e7, 3);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(alice, 1, amount, 2, true);
        vm.prank(alice);
        lusd0PP.withdraw(1, 2, true);
        assertEq(usd0PP.balanceOf(address(alice)), amount);
        // we don't get any USD0
        assertEq(stbcToken.balanceOf(address(alice)), 0);

        // deposit 1 should still exist
        (owner, amountDeposited, timestamp, usualRewards) = lusd0PP.getDeposit(1);
        assertEq(owner, alice);
        assertEq(amountDeposited, amount);
        assertEq(timestamp, currentTimestamp);
        assertEq(usualRewards, true);
    }

    function testWithdrawWithIncorrectRoundIdFails() public {
        uint256 amount = 1000 ether;
        testDeposit(amount);
        // move 180days in the future
        skip(180 days);
        yieldOracle.pushData(1e7, 3);
        skip(1 days);
        yieldOracle.pushData(1.1e7, 4);
        vm.expectRevert(abi.encodeWithSelector(InvalidOrderId.selector, 3));
        vm.prank(alice);
        lusd0PP.withdraw(1, 3, true);
    }

    function testWithdrawWithEarlyRoundIdFails() public {
        uint256 amount = 1000 ether;
        testDeposit(amount);
        // move 180days in the future
        skip(179 days);
        yieldOracle.pushData(1e7, 3);
        skip(1 days);
        yieldOracle.pushData(1.1e7, 4);
        vm.expectRevert(abi.encodeWithSelector(NotClaimableYet.selector));
        vm.prank(alice);
        lusd0PP.withdraw(1, 2, true);
    }

    function testWithdrawUsualAlreadyClaimedFail() public {
        uint256 amount = 1000 ether;
        testWithdrawUsualShouldWork(amount);
        vm.expectRevert(abi.encodeWithSelector(AlreadyClaimed.selector));
        vm.prank(alice);
        lusd0PP.withdraw(1, 2, true);
    }

    function testWithdrawUSD0AlreadyClaimedUsualFail() public {
        uint256 amount = 1000 ether;
        testWithdrawUsualShouldWork(amount);
        vm.expectRevert(abi.encodeWithSelector(AlreadyClaimed.selector));
        vm.prank(alice);
        lusd0PP.withdraw(1, 2, false);
    }

    function testWithdrawUsd0YieldFuzzingShouldWork(int256 yield) public {
        uint256 amount = 100e18;
        yield = bound(yield, 0, 1e9);

        testDeposit(amount);
        assertEq(stbcToken.balanceOf(address(alice)), 0);
        // lusd0pp must have the USD0_MINT role
        vm.prank(admin);
        registryAccess.grantRole(USD0_MINT, address(lusd0PP));
        // deposit 1 should exist
        (address owner, uint256 amountDeposited, uint256 timestamp, bool usualRewards) =
            lusd0PP.getDeposit(1);
        assertEq(owner, address(alice));
        assertEq(amountDeposited, amount);
        assertEq(timestamp, block.timestamp);
        assertEq(usualRewards, false);
        // move 180days in the future
        skip(180 days);
        yieldOracle.pushData(yield, 3);
        vm.prank(alice);
        lusd0PP.withdraw(1, 2, false);
        assertEq(usd0PP.balanceOf(address(alice)), amount);
        // rewards should be  yield % of the amount
        assertEq(stbcToken.balanceOf(address(alice)), amount * uint256(yield) / 1e9);

        // deposit 1 should not exist anymore
        (owner, amountDeposited, timestamp, usualRewards) = lusd0PP.getDeposit(1);
        assertEq(owner, address(0));
        assertEq(amountDeposited, 0);
        assertEq(timestamp, 0);
        assertEq(usualRewards, false);
    }

    function testExitEarlyShouldWork(uint256 amount) public {
        amount = bound(amount, 100, type(uint64).max);

        testDeposit(amount);
        assertEq(stbcToken.balanceOf(address(alice)), 0);
        // deposit 1 should exist
        (address owner, uint256 amountDeposited, uint256 timestamp, bool usualRewards) =
            lusd0PP.getDeposit(1);
        uint256 currentTimestamp = block.timestamp;
        assertEq(owner, address(alice));
        assertEq(amountDeposited, amount);
        assertEq(timestamp, currentTimestamp);
        assertEq(usualRewards, false);
        // move 7days in the future
        skip(7 days);
        vm.expectEmit(true, true, true, true);
        emit ExitEarly(alice, 1, amount);
        vm.prank(alice);
        lusd0PP.exitEarly(1);
        assertEq(usd0PP.balanceOf(address(alice)), amount);
        // we don't get any USD0
        assertEq(stbcToken.balanceOf(address(alice)), 0);

        // deposit 1 shouldn't exist anymore
        (owner, amountDeposited, timestamp, usualRewards) = lusd0PP.getDeposit(1);
        assertEq(owner, address(0));
        assertEq(amountDeposited, 0);
        assertEq(timestamp, 0);
        assertEq(usualRewards, false);
    }

    function testExitEarlyFailsBefore7Days() public {
        uint256 amount = 1000 ether;
        testDeposit(amount);
        assertEq(stbcToken.balanceOf(address(alice)), 0);
        uint256 curTimestamp = block.timestamp;
        skip(7 days - 1);
        vm.expectRevert(abi.encodeWithSelector(NotClaimableYet.selector));
        vm.prank(alice);
        lusd0PP.exitEarly(1);
        assertEq(usd0PP.balanceOf(address(alice)), 0);
        // we don't get any USD0
        assertEq(stbcToken.balanceOf(address(alice)), 0);

        // deposit 1 should still exist
        (address owner, uint256 amountDeposited, uint256 timestamp, bool usualRewards) =
            lusd0PP.getDeposit(1);
        assertEq(owner, alice);
        assertEq(amountDeposited, amount);
        assertEq(timestamp, curTimestamp);
        assertEq(usualRewards, false);
    }

    function testExitEarlyFailsIfNotOwner() public {
        uint256 amount = 1000 ether;
        testDeposit(amount);
        assertEq(stbcToken.balanceOf(address(alice)), 0);
        uint256 curTimestamp = block.timestamp;
        skip(7 days);
        vm.expectRevert(abi.encodeWithSelector(NotOwner.selector));
        vm.prank(bob);
        lusd0PP.exitEarly(1);
        assertEq(usd0PP.balanceOf(address(alice)), 0);
        // we don't get any USD0
        assertEq(stbcToken.balanceOf(address(alice)), 0);

        // deposit 1 should still exist
        (address owner, uint256 amountDeposited, uint256 timestamp, bool usualRewards) =
            lusd0PP.getDeposit(1);
        assertEq(owner, alice);
        assertEq(amountDeposited, amount);
        assertEq(timestamp, curTimestamp);
        assertEq(usualRewards, false);
    }
}
