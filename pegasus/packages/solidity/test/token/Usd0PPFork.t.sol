// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {ITransparentUpgradeableProxy} from
    "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {SetupTest} from "test/setup.t.sol";
import {Usd0PP} from "src/token/Usd0PP.sol";
import {IUsd0PP} from "src/interfaces/token/IUsd0PP.sol";
import {IUsd0} from "src/interfaces/token/IUsd0.sol";
import {ICurvePool} from "shared/interfaces/curve/ICurvePool.sol";
import {IDaoCollateral} from "src/interfaces/IDaoCollateral.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {
    CONTRACT_USD0PP,
    CONTRACT_USD0,
    CONTRACT_TREASURY,
    CONTRACT_DAO_COLLATERAL,
    CONTRACT_REGISTRY_ACCESS,
    BOND_DURATION_FOUR_YEAR,
    PEG_MAINTAINER_ROLE,
    CONTRACT_AIRDROP_DISTRIBUTION
} from "src/constants.sol";
import {
    BeginInPast,
    BondNotStarted,
    BondNotFinished,
    BondFinished,
    InvalidName,
    InvalidSymbol,
    AmountIsZero,
    Blacklisted,
    PARNotRequired,
    PARNotSuccessful,
    PARUSD0InputExceedsBalance,
    ApprovalFailed
} from "src/errors.sol";

import {CURVE_POOL} from "src/mock/constants.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";

contract Usd0PPForkTest is SetupTest {
    uint256 public initialUSD0 = 1e24; // 1 mil USD0
    address public rwa;
    ICurvePool public forkedCurvePool;
    address public CONTRACT_REGISTRY_MAINNET = 0x0594cb5ca47eFE1Ff25C7B8B43E221683B4Db34c;
    address public USUAL_PROXY_ADMIN_MAINNET = 0xaaDa24358620d4638a2eE8788244c6F4b197Ca16;
    address public USUAL_REGISTRY_ACCESS_ADMIN_MAINNET = 0x6e9d65eC80D69b1f508560Bc7aeA5003db1f7FB7;
    IRegistryContract public forkedRegistryContract;
    IRegistryAccess public forkedRegistryAccess;
    IUsd0PP public forkedUsd0PP;
    IUsd0 public forkedUsd0;
    IDaoCollateral public forkedDaoCollateral;

    event PARMechanismActivated(address indexed user, uint256 amount);

    function setUp() public virtual override {
        uint256 forkId = vm.createFork("eth");
        vm.selectFork(forkId);

        super.setUp();
        forkedRegistryContract = IRegistryContract(CONTRACT_REGISTRY_MAINNET);
        forkedRegistryAccess =
            IRegistryAccess(forkedRegistryContract.getContract(CONTRACT_REGISTRY_ACCESS));
        forkedDaoCollateral =
            IDaoCollateral(forkedRegistryContract.getContract(CONTRACT_DAO_COLLATERAL));
        forkedUsd0 = IUsd0(forkedRegistryContract.getContract(CONTRACT_USD0));
        forkedUsd0PP = IUsd0PP(forkedRegistryContract.getContract(CONTRACT_USD0PP));
        vm.label(address(forkedRegistryContract.getContract(CONTRACT_USD0PP)), "ForkedUsd0PP");
        vm.label(address(CURVE_POOL), "ForkedCurvePool");
        forkedCurvePool = ICurvePool(address(CURVE_POOL));

        vm.prank(USUAL_REGISTRY_ACCESS_ADMIN_MAINNET);
        forkedRegistryAccess.grantRole(PEG_MAINTAINER_ROLE, alice);

        // Deploy new implementation
        Usd0PP newImplementation = new Usd0PP();
        address usd0PPMainnet = address(forkedUsd0PP);
        ProxyAdmin usd0PPProxyAdmin = ProxyAdmin(Upgrades.getAdminAddress(usd0PPMainnet));
        bytes memory data = "";

        // Upgrade the proxy to point to the new implementation
        vm.prank(usd0PPProxyAdmin.owner());
        usd0PPProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(usd0PPMainnet)), address(newImplementation), data
        );
        address airdrop = address(0x852);
        // set CONTRACT_AIRDROP_DISTRIBUTION
        vm.prank(USUAL_REGISTRY_ACCESS_ADMIN_MAINNET);
        forkedRegistryContract.setContract(CONTRACT_AIRDROP_DISTRIBUTION, airdrop);
    }

    function _setupCurveEnvironment(uint256 USD0Amount, uint256 USD0PPAmount) internal {
        vm.prank(address(forkedDaoCollateral));
        forkedUsd0.mint(address(alice), USD0Amount + USD0PPAmount);

        vm.startPrank(address(alice));
        forkedUsd0.approve(address(forkedUsd0PP), USD0PPAmount);
        forkedUsd0PP.mint(USD0PPAmount);
        vm.stopPrank();

        assertEq(forkedUsd0PP.balanceOf(address(alice)), USD0PPAmount);
        assertEq(forkedUsd0.balanceOf(address(alice)), USD0Amount);
    }

    // Internal function to balance the curve pool (with a little more of USD0)
    function _balanceCurvePoolWithMoreUsd0() internal returns (uint256 excessUsd0) {
        uint256 usd0Balance = forkedCurvePool.balances(0);
        uint256 usd0ppBalance = forkedCurvePool.balances(1);

        if (usd0Balance > usd0ppBalance) {
            // Pool has excess USD0, we need to add USD0PP
            excessUsd0 = usd0Balance - usd0ppBalance;
            if (excessUsd0 <= 20e18) {
                excessUsd0 = 20e18 - excessUsd0;
            } else {
                excessUsd0 = excessUsd0 - 20e18;
            }
            deal(address(forkedUsd0), address(alice), excessUsd0);

            vm.startPrank(address(alice));
            forkedUsd0.approve(address(forkedUsd0PP), excessUsd0);
            forkedUsd0PP.mint(excessUsd0);
            forkedUsd0PP.approve(address(forkedCurvePool), excessUsd0);
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = 0;
            amounts[1] = excessUsd0; // Add a little less USD0PP
            forkedCurvePool.add_liquidity(amounts, 0);
            vm.stopPrank();
        } else if (usd0ppBalance > usd0Balance) {
            // Pool has excess USD0PP, we need to add USD0
            uint256 excessUsd0PP = usd0ppBalance - usd0Balance + 20e18; // Add a little more USD0
            deal(address(forkedUsd0), address(alice), excessUsd0PP);

            vm.startPrank(address(alice));
            forkedUsd0.approve(address(forkedCurvePool), excessUsd0PP);
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = excessUsd0PP;
            amounts[1] = 0;
            forkedCurvePool.add_liquidity(amounts, 0);
            vm.stopPrank();
        }

        // Verify the balance
        usd0Balance = forkedCurvePool.balances(0);
        usd0ppBalance = forkedCurvePool.balances(1);
        require(usd0Balance >= usd0ppBalance, "Pool not balanced in the right way");
        excessUsd0 = usd0Balance - usd0ppBalance;
        assertApproxEqAbs(usd0Balance, usd0ppBalance, 40e18, "Pool not balanced");

        return excessUsd0;
    }

    function _imbalanceCurvePool(uint256 additionalUsd0PP) internal {
        deal(address(forkedUsd0), address(alice), additionalUsd0PP);
        vm.startPrank(address(alice));
        forkedUsd0.approve(address(forkedUsd0PP), additionalUsd0PP);
        forkedUsd0PP.mint(additionalUsd0PP);
        forkedUsd0PP.approve(address(forkedCurvePool), additionalUsd0PP);

        // Add liquidity to the pool
        forkedUsd0PP.approve(address(forkedCurvePool), additionalUsd0PP);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = additionalUsd0PP;
        forkedCurvePool.add_liquidity(amounts, 0);
        vm.stopPrank();
    }

    function _imbalanceCurvePoolForProfit() internal returns (uint256) {
        // First, balance the pool
        _balanceCurvePoolWithMoreUsd0();

        uint256 excessUsd0PP = 1000 * 1e18; // Start with 1000 USD0PP
        uint256 profitPercentage = 0;

        while (profitPercentage <= 40) {
            // 40 basis points = 0.4%
            // Imbalance the pool until we get a profit of more than 0.4%
            _imbalanceCurvePool(excessUsd0PP);

            uint256 usd0Balance = forkedCurvePool.balances(0);
            uint256 usd0ppBalance = forkedCurvePool.balances(1);

            uint256 usd0ToSwap = (usd0ppBalance - usd0Balance) / 2;
            uint256 expectedUsd0pp = forkedCurvePool.get_dy(0, 1, usd0ToSwap);

            // Calculate profit
            if (expectedUsd0pp <= usd0ToSwap) {
                excessUsd0PP += 1000 * 1e18; // Increase by 1000 USD0PP and try again
                continue;
            } else {
                uint256 profit = expectedUsd0pp - usd0ToSwap;
                profitPercentage = (profit * 10_000) / usd0ToSwap;

                if (profitPercentage <= 40) {
                    excessUsd0PP += 1000 * 1e18; // Increase by 1000 USD0PP and try again
                }
            }
        }
        return forkedCurvePool.balances(1) - forkedCurvePool.balances(0);
    }

    function testManipulateCurvePool() public {
        _imbalanceCurvePoolForProfit();
        _balanceCurvePoolWithMoreUsd0();
    }

    function testAddLiquidityToCurvePool() public {
        string memory name = ICurvePool(forkedCurvePool).name();
        assertEq(name, "USD0/USD0++");
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = forkedCurvePool.balances(0);
        amounts[1] = forkedCurvePool.balances(1);

        assertEq(forkedCurvePool.coins(0), address(forkedUsd0));
        assertEq(forkedCurvePool.coins(1), address(forkedUsd0PP));

        _setupCurveEnvironment(amounts[0], amounts[1]);
        assertEq(forkedUsd0.balanceOf(address(alice)), amounts[0]);
        assertEq(forkedUsd0PP.balanceOf(address(alice)), amounts[1]);

        vm.startPrank(alice);
        forkedUsd0.approve(address(forkedCurvePool), type(uint256).max);
        forkedUsd0PP.approve(address(forkedCurvePool), type(uint256).max);

        uint256 lpAmount = forkedCurvePool.add_liquidity(amounts, 0);
        assertGt(lpAmount, 0);
        vm.stopPrank();
    }

    function testBalanceCurvePool() public {
        // Set up the environment
        _balanceCurvePoolWithMoreUsd0();

        uint256 usd0Balance = forkedCurvePool.balances(0);
        uint256 usd0ppBalance = forkedCurvePool.balances(1);

        assertApproxEqAbs(usd0Balance, usd0ppBalance, 40e18 ether);
        vm.stopPrank();
    }

    function testBalanceCurvePoolThroughParMechanismMinimumProfit() public {
        uint256 excessUsd0PP = _imbalanceCurvePoolForProfit();

        // Calculate swap amounts
        uint256 usd0ToAdd = excessUsd0PP / 2;
        uint256 expectedUsd0pp = forkedCurvePool.get_dy(0, 1, usd0ToAdd);
        assertGt(expectedUsd0pp, usd0ToAdd, "Swap should be profitable");

        uint256 expectedProfit = expectedUsd0pp - usd0ToAdd;

        vm.startPrank(address(alice));
        forkedUsd0PP.approve(address(forkedCurvePool), type(uint256).max);
        forkedUsd0.approve(address(forkedCurvePool), type(uint256).max);
        assertTrue(
            forkedRegistryAccess.hasRole(PEG_MAINTAINER_ROLE, alice),
            "Alice should have the peg maintainer role"
        );

        vm.expectEmit(true, true, false, true);
        emit PARMechanismActivated(alice, expectedProfit);
        forkedUsd0PP.triggerPARMechanismCurvepool(usd0ToAdd, expectedProfit);

        uint256 usd0BalanceAfter = forkedCurvePool.balances(0);
        uint256 usd0ppBalanceAfter = forkedCurvePool.balances(1);
        assertLt(usd0ppBalanceAfter, usd0BalanceAfter, "Pool should now have more USD0 than USD0PP");

        vm.stopPrank();
    }

    function testTriggerPARMechanismCurvepoolRevertsIfAmountIsZero() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        forkedUsd0PP.triggerPARMechanismCurvepool(0, 1);

        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        forkedUsd0PP.triggerPARMechanismCurvepool(1, 0);
        vm.stopPrank();
    }

    function testBalanceCurvePoolThroughParMechanism1() public {
        // Set up the environment
        _imbalanceCurvePoolForProfit();

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = forkedCurvePool.balances(1);
        _setupCurveEnvironment(amounts[0], amounts[1]);

        uint256 usd0Balance = forkedCurvePool.balances(0);
        uint256 usd0ppBalance = forkedCurvePool.balances(1);
        uint256 usd0ToAdd = (usd0ppBalance - usd0Balance) / 2;
        uint256 expectedUsd0pp = forkedCurvePool.get_dy(0, 1, usd0ToAdd);

        //NOTE: even though there is an imbalance, it is not enough to trigger the par mechanism unless its large enough to cover the exchange fee
        assertGt(usd0ppBalance, usd0Balance);
        assertGt(expectedUsd0pp, usd0ToAdd); // we actually want more usd0pp than USD0 we sent since we can unwrap 1:1

        vm.startPrank(address(alice));
        forkedUsd0PP.approve(address(forkedCurvePool), type(uint256).max);
        forkedUsd0.approve(address(forkedCurvePool), type(uint256).max);
        forkedCurvePool.add_liquidity(amounts, 0);

        usd0Balance = forkedCurvePool.balances(0);
        usd0ppBalance = forkedCurvePool.balances(1);
        usd0ToAdd = (usd0ppBalance - usd0Balance) / 2;
        expectedUsd0pp = forkedCurvePool.get_dy(0, 1, usd0ToAdd);

        //NOTE: the pool is now imbalanced enough to get back more USD0PP than USD0 we sent
        assertGt(usd0ppBalance, usd0Balance);
        assertGt(expectedUsd0pp, usd0ToAdd); // this is now a successful arb opportunity

        //check if we have that much USD0 and actually swap it, then check the   pool is balanced
        assertGt(forkedUsd0.balanceOf(address(forkedUsd0PP)), usd0ToAdd);

        forkedUsd0PP.approve(address(forkedCurvePool), type(uint256).max);
        forkedUsd0.approve(address(forkedCurvePool), type(uint256).max);
        uint256 expectedProfit = expectedUsd0pp - usd0ToAdd;
        assertTrue(
            forkedRegistryAccess.hasRole(PEG_MAINTAINER_ROLE, alice),
            "Alice should have the peg maintainer role"
        );
        uint256 treasuryBalanceBeforePAR =
            forkedUsd0.balanceOf(address(forkedRegistryContract.getContract(CONTRACT_TREASURY)));
        forkedUsd0PP.triggerPARMechanismCurvepool(usd0ToAdd, expectedProfit); // no slippage past what we expected
        uint256 treasuryBalanceAfterPAR =
            forkedUsd0.balanceOf(address(forkedRegistryContract.getContract(CONTRACT_TREASURY)));

        assertEq(treasuryBalanceAfterPAR - treasuryBalanceBeforePAR, expectedProfit);

        vm.stopPrank();
    }

    function testBalanceCurvePoolThroughParMechanismRevertsIfApprovalFails() public {
        // Set up the environment
        _imbalanceCurvePoolForProfit();

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = forkedCurvePool.balances(1);
        _setupCurveEnvironment(amounts[0], amounts[1]);

        uint256 usd0Balance = forkedCurvePool.balances(0);
        uint256 usd0ppBalance = forkedCurvePool.balances(1);
        uint256 usd0ToAdd = (usd0ppBalance - usd0Balance) / 2;
        uint256 expectedUsd0pp = forkedCurvePool.get_dy(0, 1, usd0ToAdd);

        vm.startPrank(address(alice));
        forkedUsd0PP.approve(address(forkedCurvePool), type(uint256).max);
        forkedUsd0.approve(address(forkedCurvePool), type(uint256).max);
        forkedCurvePool.add_liquidity(amounts, 0);

        usd0Balance = forkedCurvePool.balances(0);
        usd0ppBalance = forkedCurvePool.balances(1);
        usd0ToAdd = (usd0ppBalance - usd0Balance) / 2;
        expectedUsd0pp = forkedCurvePool.get_dy(0, 1, usd0ToAdd);

        forkedUsd0PP.approve(address(forkedCurvePool), type(uint256).max);
        forkedUsd0.approve(address(forkedCurvePool), type(uint256).max);
        uint256 expectedProfit = expectedUsd0pp - usd0ToAdd;

        vm.mockCall(
            address(forkedUsd0),
            abi.encodeWithSelector(forkedUsd0.approve.selector),
            abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(ApprovalFailed.selector));
        forkedUsd0PP.triggerPARMechanismCurvepool(usd0ToAdd, expectedProfit);

        vm.stopPrank();
    }

    function testBalanceCurvePoolThroughParMechanismRevertsIfParNotRequired() public {
        // Set up the environment
        _imbalanceCurvePoolForProfit();

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = forkedCurvePool.balances(1);
        _setupCurveEnvironment(amounts[0], amounts[1]);

        uint256 usd0Balance = forkedCurvePool.balances(0);
        uint256 usd0ppBalance = forkedCurvePool.balances(1);
        uint256 usd0ToAdd = (usd0ppBalance - usd0Balance) / 2;
        uint256 expectedUsd0pp = forkedCurvePool.get_dy(0, 1, usd0ToAdd);

        vm.startPrank(address(alice));
        forkedUsd0PP.approve(address(forkedCurvePool), type(uint256).max);
        forkedUsd0.approve(address(forkedCurvePool), type(uint256).max);
        forkedCurvePool.add_liquidity(amounts, 0);

        usd0Balance = forkedCurvePool.balances(0);
        usd0ppBalance = forkedCurvePool.balances(1);
        usd0ToAdd = (usd0ppBalance - usd0Balance) / 2;
        expectedUsd0pp = forkedCurvePool.get_dy(0, 1, usd0ToAdd);

        forkedUsd0PP.approve(address(forkedCurvePool), type(uint256).max);
        forkedUsd0.approve(address(forkedCurvePool), type(uint256).max);
        uint256 expectedProfit = expectedUsd0pp - usd0ToAdd;

        vm.mockCall(
            address(forkedCurvePool),
            abi.encodeWithSelector(forkedCurvePool.exchange.selector),
            abi.encode(0)
        );
        vm.expectRevert(abi.encodeWithSelector(PARNotRequired.selector));
        forkedUsd0PP.triggerPARMechanismCurvepool(usd0ToAdd, expectedProfit);

        vm.stopPrank();
    }

    function testTriggerPARMechanismCurvepoolRevertIfNotPegMaintainer() public {
        uint256 parUsd0Amount = 1e23; // 100_000 USD0
        uint256 minimumGain = 1e21; // 1_000 USD0

        _setupCurveEnvironment(initialUSD0, parUsd0Amount);

        vm.prank(jack);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        forkedUsd0PP.triggerPARMechanismCurvepool(parUsd0Amount, minimumGain);
    }

    function testTriggerPARMechanismRevertIfBondNotStarted() public {
        uint256 parUsd0Amount = 1e23;
        uint256 minimumGain = 1e21;
        _setupCurveEnvironment(initialUSD0, parUsd0Amount);
        vm.warp(forkedUsd0PP.getStartTime() - 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BondNotStarted.selector));
        forkedUsd0PP.triggerPARMechanismCurvepool(parUsd0Amount, minimumGain);
    }

    function testTriggerPARMechanismRevertOnInsufficientUSD0() public {
        // Balance the pool initially
        _balanceCurvePoolWithMoreUsd0();
        _imbalanceCurvePool(2 * forkedUsd0.balanceOf(address(forkedUsd0PP)) + 1e18);

        uint256 usd0ToAdd = forkedUsd0.balanceOf(address(forkedUsd0PP)) * 2;
        uint256 expectedProfit = 1e18;

        vm.startPrank(address(alice));
        forkedUsd0PP.approve(address(forkedCurvePool), type(uint256).max);
        forkedUsd0.approve(address(forkedCurvePool), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(PARUSD0InputExceedsBalance.selector));
        forkedUsd0PP.triggerPARMechanismCurvepool(usd0ToAdd, expectedProfit);

        vm.stopPrank();
    }

    function testTriggerPARMechanismRevertOnBalancedPool() public {
        // Balance the pool initially
        _balanceCurvePoolWithMoreUsd0();

        uint256 usd0ToAdd = forkedUsd0.balanceOf(address(forkedUsd0PP));
        uint256 expectedProfit = 1e18;

        vm.startPrank(address(alice));
        forkedUsd0PP.approve(address(forkedCurvePool), type(uint256).max);
        forkedUsd0.approve(address(forkedCurvePool), type(uint256).max);

        //@notice, this revert would only trigger if the curvepool did not revert on its own given that we didn't receive more USD0PP than we spent USD0.
        //vm.expectRevert(PARNotRequired.selector));
        vm.expectRevert("Exchange resulted in fewer coins than expected");
        forkedUsd0PP.triggerPARMechanismCurvepool(usd0ToAdd, expectedProfit);

        vm.stopPrank();
    }
}
