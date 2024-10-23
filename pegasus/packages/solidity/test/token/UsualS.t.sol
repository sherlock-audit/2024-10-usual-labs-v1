// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SetupTest} from "test/setup.t.sol";
import {
    USUALS_BURN,
    USUALS_TOTAL_SUPPLY,
    USUALSP,
    USUALSName,
    USUALSSymbol,
    BLACKLIST_ROLE
} from "src/constants.sol";
import {NotAuthorized, Blacklisted, SameValue} from "src/errors.sol";
import {UsualS} from "src/token/UsualS.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";

import {Pausable} from "openzeppelin-contracts/utils/Pausable.sol";

// @title: UsualS test contract
// @notice: Contract to test UsualS token implementation

contract UsualSTest is SetupTest {
    event Blacklist(address account);
    event UnBlacklist(address account);
    event TransferPaused(bool isPaused);
    event Stake(address account, uint256 amount);

    function setUp() public virtual override {
        super.setUp();
    }

    function testInitializeShouldFailWithWrongValues() public {
        _resetInitializerImplementation(address(usualS));
        vm.expectRevert(abi.encodeWithSelector(NullContract.selector));
        usualS.initialize(IRegistryContract(address(0)), "", "");

        vm.expectRevert(abi.encodeWithSelector(InvalidName.selector));
        usualS.initialize(IRegistryContract(address(registryContract)), "", "");

        vm.expectRevert(abi.encodeWithSelector(InvalidSymbol.selector));
        usualS.initialize(IRegistryContract(address(registryContract)), "USUALS", "");
    }

    function testName() external view {
        assertEq(USUALSName, usualS.name());
    }

    function testSymbol() external view {
        assertEq(USUALSSymbol, usualS.symbol());
    }

    function testTotalSupply() external view {
        assertEq(USUALS_TOTAL_SUPPLY, usualS.totalSupply());
    }

    function testInitializeShouldFailWithNullAddress() public {
        _resetInitializerImplementation(address(usualS));
        vm.expectRevert(abi.encodeWithSelector(NullContract.selector));
        usualS.initialize(IRegistryContract(address(0)), "USUALS", "USUALS");
    }

    function testConstructor() public {
        UsualS usualS = new UsualS();
        assertTrue(address(usualS) != address(0));
    }

    function testAnyoneCanCreateUsualS() public {
        UsualS usualS = new UsualS();
        _resetInitializerImplementation(address(usualS));
        usualS.initialize(IRegistryContract(registryContract), "USUALS", "USUALS");
        assertTrue(address(usualS) != address(0));
    }

    function testCreationOfUsualToken() public {
        _resetInitializerImplementation(address(usualS));
        usualS.initialize(IRegistryContract(registryContract), "USUALS", "USUALS");
    }

    function setup_MintToAlice(uint256 amount) public {
        deal(address(usualS), alice, amount);
        assertEq(usualS.balanceOf(alice), amount);
        vm.stopPrank();
    }

    function testBurnFrom() public {
        setup_MintToAlice(100e18);
        vm.prank(admin);
        usualS.burnFrom(alice, 8e18);

        assertEq(usualS.totalSupply(), USUALS_TOTAL_SUPPLY - 8e18);
        assertEq(usualS.balanceOf(alice), 92e18);
    }

    function testBurnFromFail() public {
        setup_MintToAlice(100e18);

        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualS.burnFrom(alice, 8e18);

        assertEq(usualS.balanceOf(alice), 100e18);
    }

    function testBurn() public {
        setup_MintToAlice(100e18);
        vm.prank(alice);
        usualS.transfer(admin, 8e18);

        vm.prank(admin);
        usualS.burn(8e18);

        assertEq(usualS.balanceOf(admin), 0);
    }

    function testBurnFail() public {
        setup_MintToAlice(100e18);
        vm.prank(alice);

        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualS.burn(8e18);
    }

    function testApprove() public {
        assertTrue(usualS.approve(alice, 1e18));
        assertEq(usualS.allowance(address(this), alice), 1e18);
    }

    function testTransfer() external {
        setup_MintToAlice(2e18);
        vm.startPrank(alice);
        usualS.transfer(bob, 0.5e18);
        assertEq(usualS.balanceOf(bob), 0.5e18);
        assertEq(usualS.balanceOf(alice), 1.5e18);
        vm.stopPrank();
    }

    function testTransferFrom() external {
        setup_MintToAlice(2e18);
        vm.prank(alice);
        usualS.approve(address(this), 1e18);
        assertTrue(usualS.transferFrom(alice, bob, 0.7e18));
        assertEq(usualS.allowance(alice, address(this)), 1e18 - 0.7e18);
        assertEq(usualS.balanceOf(alice), 2e18 - 0.7e18);
        assertEq(usualS.balanceOf(bob), 0.7e18);
    }

    function testTransferFromWithPermit(uint256 amount) public {
        amount = bound(amount, 100, USUALS_TOTAL_SUPPLY);
        setup_MintToAlice(amount);

        vm.startPrank(alice);
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) =
            _getSelfPermitData(address(usualS), alice, alicePrivKey, bob, amount, deadline);

        IERC20Permit(address(usualS)).permit(alice, bob, amount, deadline, v, r, s);

        vm.stopPrank();
        vm.prank(bob);
        usualS.transferFrom(alice, bob, amount);

        assertEq(usualS.balanceOf(bob), amount);
        assertEq(usualS.balanceOf(alice), 0);
    }

    function testPauseUnPause() external {
        setup_MintToAlice(2e18);

        vm.prank(pauser);
        usualS.pause();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        usualS.transfer(bob, 1e18);
        vm.prank(admin);
        usualS.unpause();
        vm.prank(alice);
        usualS.transfer(bob, 1e18);
    }

    function testPauseUnPauseShouldFailWhenNotAuthorized() external {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualS.pause();
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualS.unpause();
    }

    function testBlacklistUser() external {
        setup_MintToAlice(2e18);

        vm.startPrank(blacklistOperator);
        usualS.blacklist(alice);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        usualS.blacklist(alice);
        vm.stopPrank();

        vm.assertTrue(usualS.isBlacklisted(alice));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Blacklisted.selector));
        usualS.transfer(bob, 1e18);

        vm.startPrank(blacklistOperator);
        usualS.unBlacklist(alice);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        usualS.unBlacklist(alice);
        vm.stopPrank();

        vm.prank(alice);
        usualS.transfer(bob, 1e18);
    }

    function testBlacklistShouldRevertIfAddressIsZero() external {
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        usualS.blacklist(address(0));
    }

    function testBlacklistAndUnBlacklistEmitsEvents() external {
        setup_MintToAlice(2e18);
        vm.startPrank(blacklistOperator);
        vm.expectEmit();
        emit Blacklist(alice);
        usualS.blacklist(alice);

        vm.startPrank(blacklistOperator);
        vm.expectEmit();
        emit UnBlacklist(alice);
        usualS.unBlacklist(alice);
    }

    function testOnlyAdminCanUseBlacklist(address user) external {
        vm.assume(user != blacklistOperator);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualS.blacklist(alice);

        vm.prank(blacklistOperator);
        usualS.blacklist(alice);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualS.unBlacklist(alice);
    }

    function testSendToStaking() external {
        setup_MintToAlice(2e18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualS.stakeAll();

        vm.startPrank(address(usualSP));
        usualS.stakeAll();
        vm.assertEq(usualS.balanceOf(address(usualS)), 0);
        vm.assertEq(usualS.balanceOf(address(usualSP)), USUALS_TOTAL_SUPPLY);
    }

    function testSendToStakingEmitEvent() external {
        setup_MintToAlice(2e18);
        vm.startPrank(address(usualSP));
        vm.expectEmit();
        emit Stake(address(usualSP), USUALS_TOTAL_SUPPLY);
        usualS.stakeAll();
    }
}
