// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {CONTRACT_ORACLE_USUAL, BOND_DURATION_FOUR_YEAR} from "src/constants.sol";
import {USYC, USDC} from "src/mock/constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Usd0PP} from "src/token/Usd0PP.sol";
import {DaoCollateral} from "src/daoCollateral/DaoCollateral.sol";
import {SigUtils} from "test/utils/sigUtils.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IUSYC} from "test/interfaces/IUSYC.sol";
import {IUSYCAuthority, USYCRole} from "test/interfaces/IUSYCAuthority.sol";
import {ICurvePool} from "shared/interfaces/curve/ICurvePool.sol";
import {Usd0PPHarness} from "src/mock/token/Usd0PPHarness.sol";
import {BaseDeploymentTest} from "test/deployment/baseDeployment.t.sol";

/// @author  Usual Tech Team
/// @title   ERC20 LayerZero Deployment Script
/// @dev     Do not use in production this is for research purposes only
/// @dev     See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
/// @notice  ERC20 using LayerZero deployment script
contract DeploymentTest is BaseDeploymentTest {
    uint256 amount = 100 ether;

    function setUp() public override {
        super.setUp();
    }

    function testCurvePool() public {
        _mintUSYC();
        uint256 aliceUSDC = 100e6;
        uint256 aliceusRWA = 100e6;
        _dealUSDC(alice, aliceUSDC);
        vm.label(address(rwa), "rwa");
        vm.label(address(curvePool), "curvePool");
        vm.startPrank(alice);
        IERC20(address(rwa)).approve(address(daoCollateral), type(uint256).max);
        USD0.approve(curvePool, type(uint256).max);
        // Swap RWA for USD0
        daoCollateral.swap(address(rwa), aliceusRWA, 0);
        uint256 aliceUSD0 = USD0.balanceOf(alice);
        IERC20(USDC).approve(curvePool, type(uint256).max);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = aliceUSDC;
        amounts[1] = aliceUSD0;
        uint256 lpAmount = ICurvePool(curvePool).add_liquidity(amounts, 0);
        assertGt(lpAmount, 20e19);
        vm.stopPrank();
        string memory name = ICurvePool(curvePool).name();
        assertEq(name, "USD0/USDC");
        assertEq(USD0.balanceOf(alice), 0);
    }

    function testOracle() public view {
        require(
            deploy.registryContract().getContract(CONTRACT_ORACLE_USUAL) != address(0),
            "Deployment failed"
        );
        uint256 quote = deploy.usualOracle().getQuote(address(USD0), 1e18);
        assertEq(quote, 1 ether);
    }

    function testSwap() public {
        _mintUSYC();
        require(address(daoCollateral) != address(0), "Deployment failed");

        assertEq(address(deploy.USD0()), address(USD0));

        assertEq(USD0.balanceOf(alice), 0);
        vm.startPrank(alice);
        // rwa.mint(alice, amount);
        IERC20(address(rwa)).approve(address(daoCollateral), amount);
        // we swap amount  RWA  for  amount STBC
        daoCollateral.swap(address(rwa), amount, 0);
        vm.stopPrank();
        assertGt(USD0.balanceOf(alice), 0);
    }
    // test redeem works

    function testRedeem() public {
        testSwap();
        assertEq(IERC20(address(rwa)).balanceOf(alice), 0);
        uint256 balance = USD0.balanceOf(alice);
        assertGt(balance, 0);

        deal(USYC, treasury, type(uint128).max);

        vm.startPrank(alice);
        // we redeem amount STBC for amount RWA
        daoCollateral.redeem(address(rwa), balance, 0);
        vm.stopPrank();
        assertGt(IERC20(address(rwa)).balanceOf(alice), 0);
        assertEq(USD0.balanceOf(alice), 0);
    }

    function testUsd0PP() public {
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + BOND_DURATION_FOUR_YEAR;
        vm.prank(usual);
        Usd0PPHarness usd0PP180 = new Usd0PPHarness();
        _resetInitializerImplementation(address(usd0PP180));
        usd0PP180.initialize(
            address(registryContract), "UsualDAO Bond 180", "USD0PP lsUSD", startTime
        );
        usd0PP180.initializeV1();
        // prank the usual dao to allow the usd0PP180 to receive

        assertEq(usd0PP180.name(), "UsualDAO Bond 180");
        assertEq(usd0PP180.symbol(), "USD0PP lsUSD");
        assertEq(usd0PP180.decimals(), 18);
        assertEq(usd0PP180.getStartTime(), startTime);
        assertEq(usd0PP180.getEndTime(), endTime);
        testSwap();

        uint256 balBefore = USD0.balanceOf(alice);
        vm.startPrank(address(alice));
        // swap for USD0
        // approve USD0 to usd0PP180
        USD0.approve(address(usd0PP180), amount);
        skip(244 days);
        usd0PP180.mint(amount);
        assertEq(usd0PP180.balanceOf(address(alice)), amount);
        skip(1218 days);
        usd0PP180.unwrap();
        assertEq(USD0.balanceOf(address(alice)), balBefore);
        vm.stopPrank();
    }

    function _mintUSYC() internal {
        address authority = IUSYC(USYC).authority();
        address authOwner = IUSYCAuthority(authority).owner();

        vm.startPrank(authOwner);
        IUSYCAuthority(authority).setUserRole(address(this), USYCRole.System_FundAdmin, true);
        IUSYCAuthority(authority).setUserRole(alice, USYCRole.Investor_SDYFDomestic, true);
        IUSYCAuthority(authority).setUserRole(bob, USYCRole.Investor_SDYFDomestic, true);
        IUSYCAuthority(authority).setUserRole(treasury, USYCRole.Investor_SDYFDomestic, true);
        IUSYCAuthority(authority).setUserRole(
            address(this), USYCRole.Investor_MFFeederDomestic, true
        );
        IUSYCAuthority(authority).setPublicCapability(USYC, ERC20.transferFrom.selector, true);

        bool canTransfer =
            IUSYCAuthority(authority).canCall(address(this), USYC, ERC20.transfer.selector);
        assertTrue(canTransfer, "Can't transfer");

        vm.stopPrank();

        IUSYC(USYC).setMinterAllowance(address(this), amount * 2);

        IUSYC(USYC).mint(address(this), amount * 2);

        IUSYC(USYC).transfer(alice, amount);
        IUSYC(USYC).transfer(bob, amount);
    }

    function _resetInitializerImplementation(address implementation) internal {
        // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
        bytes32 INITIALIZABLE_STORAGE =
            0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
        // Set the storage slot to uninitialized
        vm.store(address(implementation), INITIALIZABLE_STORAGE, 0);
    }
}
