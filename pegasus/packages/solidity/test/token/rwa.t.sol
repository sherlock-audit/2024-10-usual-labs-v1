// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {RwaMock} from "src/mock/rwaMock.sol";
import {ERC20Whitelist} from "src/mock/ERC20Whitelist.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import {SetupTest} from "../setup.t.sol";

contract RwaTest is SetupTest {
    using SafeERC20 for RwaMock;

    RwaMock public token;

    function setUp() public override {
        super.setUp();
        vm.startPrank(address(admin));
        token = new RwaMock("FR fdn Fiat Token USD", "USYC", 6, address(registryContract));

        // alice and bucketDistribution needs to be whitelisted
        // user needs to be whitelisted
        ERC20Whitelist(address(token)).whitelist(alice);
        ERC20Whitelist(address(token)).whitelist(bob);
        vm.stopPrank();
    }

    function testName() external view {
        assertEq("FR fdn Fiat Token USD", token.name());
    }

    function testSymbol() external view {
        assertEq("USYC", token.symbol());
    }

    function testMint() public {
        token.mint(alice, 2e18);
        assertEq(token.totalSupply(), token.balanceOf(alice));
    }

    function testMintZero() public {
        vm.expectRevert("Address must be a valid address");
        token.mint(address(0), 2e18);
    }

    function testBurn() public {
        token.mint(alice, 10e18);
        assertEq(token.balanceOf(alice), 10e18);

        token.burnFrom(alice, 8e18);

        assertEq(token.totalSupply(), 2e18);
        assertEq(token.balanceOf(alice), 2e18);
    }

    function testBurnZero() public {
        token.mint(alice, 10e18);
        assertEq(token.balanceOf(alice), 10e18);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0))
        );
        token.burnFrom(address(0), 8e18);
    }

    function testApprove() public {
        assertTrue(token.approve(alice, 1e18));
        assertEq(token.allowance(address(this), alice), 1e18);
    }

    function testIncreaseAllowance() external {
        assertEq(token.allowance(address(this), alice), 0);
        token.safeIncreaseAllowance(alice, 2e18);
        assertEq(token.allowance(address(this), alice), 2e18);
    }

    function testDecreaseAllowance() external {
        testApprove();
        token.safeDecreaseAllowance(alice, 0.5e18);
        assertEq(token.allowance(address(this), alice), 0.5e18);
    }

    function testTransfer() external {
        testMint();
        vm.startPrank(alice);
        token.transfer(bob, 0.5e18);
        assertEq(token.balanceOf(bob), 0.5e18);
        assertEq(token.balanceOf(alice), 1.5e18);
        vm.stopPrank();
    }

    function testTransferFrom() external {
        testMint();
        vm.prank(alice);
        token.approve(address(this), 1e18);
        assertTrue(token.transferFrom(alice, bob, 0.7e18));
        assertEq(token.allowance(alice, address(this)), 1e18 - 0.7e18);
        assertEq(token.balanceOf(alice), 2e18 - 0.7e18);
        assertEq(token.balanceOf(bob), 0.7e18);
    }

    function testFailMintToZero() external {
        token.mint(address(0), 1e18);
    }

    function testFailBurnFromZero() external {
        token.burnFrom(address(0), 1e18);
    }

    function testFailBurnInsufficientBalance() external {
        testMint();
        vm.prank(alice);
        token.burnFrom(alice, 3e18);
    }

    function testFailApproveToZeroAddress() external {
        token.approve(address(0), 1e18);
    }

    function testFailApproveFromZeroAddress() external {
        vm.prank(address(0));
        token.approve(alice, 1e18);
    }

    function testFailTransferToZeroAddress() external {
        testMint();
        vm.prank(alice);
        token.transfer(address(0), 1e18);
    }

    function testFailTransferFromZeroAddress() external {
        testBurn();
        vm.prank(address(0));
        token.transfer(alice, 1e18);
    }

    function testFailTransferInsufficientBalance() external {
        testMint();
        vm.prank(alice);
        token.transfer(bob, 3e18);
    }

    function testFailTransferFromInsufficientApprove() external {
        testMint();
        vm.prank(alice);
        token.approve(address(this), 1e18);
        token.transferFrom(alice, bob, 2e18);
    }

    function testFailTransferFromInsufficientBalance() external {
        testMint();
        vm.prank(alice);
        token.approve(address(this), type(uint256).max);

        token.transferFrom(alice, bob, 3e18);
    }

    function testMintFuzzing(uint256 amount) public {
        token.mint(alice, amount);
        assertEq(token.totalSupply(), token.balanceOf(alice));
    }

    function testBurnFuzzing(uint256 amount) public {
        token.mint(alice, 10e18);
        if (amount > token.balanceOf(alice)) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector,
                    alice,
                    uint256(10e18),
                    uint256(amount)
                )
            );
            token.burnFrom(alice, amount);
            return;
        } else {
            token.burnFrom(alice, amount);
        }

        assertEq(token.totalSupply(), 10e18 - amount);
        assertEq(token.balanceOf(alice), 10e18 - amount);
    }

    function testApproveFuzzing(uint256 amount) public {
        assertTrue(token.approve(alice, amount));
        assertEq(token.allowance(address(this), alice), amount);
    }

    function testIncreaseAllowanceFuzzing(uint256 amount) external {
        assertEq(token.allowance(address(this), alice), 0);
        token.safeIncreaseAllowance(alice, amount);
        assertEq(token.allowance(address(this), alice), amount);
    }

    function testDecreaseAllowanceFuzzing(uint256 amount) external {
        testApproveFuzzing(amount);
        token.safeDecreaseAllowance(alice, amount);
        assertEq(token.allowance(address(this), alice), 0);
    }
}
