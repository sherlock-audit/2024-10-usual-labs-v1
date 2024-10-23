// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {
    USDC,
    USD0PP_MAINNET,
    USUAL_MULTISIG_MAINNET,
    REGISTRY_ACCESS_MAINNET,
    USD0_MAINNET,
    DAO_COLLATERAL_MAINNET,
    MORPHO_CHAINLINK_ORACLE_USDC_SDAI,
    MORPHO_MAINNET,
    ADAPTIVE_CURVE_IRM
} from "src/mock/constants.sol";
import {Usd0PP} from "src/token/Usd0PP.sol";
import {Usd0} from "src/token/Usd0.sol";
import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {Id, IMorpho, Market, MarketParams, Position} from "shared/interfaces/morpho/IMorpho.sol";
import {IOracle} from "shared/interfaces/morpho/IOracle.sol";
import {MarketParamsLib} from "shared/MarketParamsLib.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {BaseDeploymentTest} from "test/deployment/baseDeployment.t.sol";

contract MorphoTest is BaseDeploymentTest {
    using MarketParamsLib for MarketParams;

    /// @notice Emitted on supply of collateral.
    /// @param id The market id.
    /// @param caller The caller.
    /// @param onBehalf The owner of the modified position.
    /// @param assets The amount of collateral supplied.
    event SupplyCollateral(
        Id indexed id, address indexed caller, address indexed onBehalf, uint256 assets
    );

    /// @notice Emitted on withdrawal of collateral.
    /// @param id The market id.
    /// @param caller The caller.
    /// @param onBehalf The owner of the modified position.
    /// @param receiver The address that received the withdrawn collateral.
    /// @param assets The amount of collateral withdrawn.
    event WithdrawCollateral(
        Id indexed id,
        address caller,
        address indexed onBehalf,
        address indexed receiver,
        uint256 assets
    );

    /// @notice Emitted on liquidation of a position.
    /// @param id The market id.
    /// @param caller The caller.
    /// @param borrower The borrower of the position.
    /// @param repaidAssets The amount of assets repaid. May be 1 over the corresponding market's `totalBorrowAssets`.
    /// @param repaidShares The amount of shares burned.
    /// @param seizedAssets The amount of collateral seized.
    /// @param badDebtAssets The amount of assets of bad debt realized.
    /// @param badDebtShares The amount of borrow shares of bad debt realized.
    event Liquidate(
        Id indexed id,
        address indexed caller,
        address indexed borrower,
        uint256 repaidAssets,
        uint256 repaidShares,
        uint256 seizedAssets,
        uint256 badDebtAssets,
        uint256 badDebtShares
    );

    /// @notice Emitted when creating a market.
    /// @param id The market id.
    /// @param marketParams The market that was created.
    event CreateMarket(Id indexed id, MarketParams marketParams);

    Id id;
    MarketParams marketParams;
    Usd0PP usd0PP;
    uint256 constant LLTV = 980_000_000_000_000_000;

    function setUp() public override {
        super.setUp();
        _mintUSYC(100 ether);
        USD0 = Usd0(USD0_MAINNET);
    }

    function testMarketCreationShouldWork() public {
        IMorpho morpho = IMorpho(MORPHO_MAINNET);
        usd0PP = Usd0PP(USD0PP_MAINNET);
        marketParams = MarketParams({
            loanToken: USDC,
            collateralToken: USD0PP_MAINNET,
            oracle: MORPHO_CHAINLINK_ORACLE_USDC_SDAI,
            irm: ADAPTIVE_CURVE_IRM,
            lltv: LLTV
        });
        id = marketParams.id();
        // update the price returned by the oracle so as not to depend on the network for our tests
        vm.mockCall(
            MORPHO_CHAINLINK_ORACLE_USDC_SDAI,
            abi.encodeWithSelector(IOracle.price.selector),
            abi.encode(1.1e24)
        );
        vm.expectEmit(true, true, true, true);
        emit CreateMarket(id, marketParams);
        morpho.createMarket(marketParams);
        Market memory USD0Market = morpho.market(id);
        assertEq(USD0Market.totalSupplyAssets, 0);
        assertEq(USD0Market.totalSupplyShares, 0);
        assertEq(USD0Market.totalBorrowAssets, 0);
        assertEq(USD0Market.totalBorrowShares, 0);
        assertEq(USD0Market.lastUpdate, block.timestamp);
        assertEq(USD0Market.fee, 0);
    }

    function testSupplyAssetsShouldWork(uint256 amountUSDC) public {
        amountUSDC = bound(amountUSDC, 1, (type(uint128).max / 1e6));
        testMarketCreationShouldWork();
        IMorpho morpho = IMorpho(MORPHO_MAINNET);
        // empty data
        bytes memory data = "";
        // mint USDC
        _dealUSDC(bob, amountUSDC);
        // allow usdc
        vm.prank(bob);
        IERC20(USDC).approve(MORPHO_MAINNET, amountUSDC);
        // supply usdC to the market
        vm.prank(bob);
        morpho.supply(marketParams, amountUSDC, 0, bob, data);
        // check position
        Position memory position = morpho.position(id, bob);
        assertEq(position.supplyShares, amountUSDC * 1e6);
        assertEq(position.borrowShares, 0);
        assertEq(position.collateral, 0);
    }

    function _supplyCollateral(uint256 amountUSD0PP) public {
        IMorpho morpho = IMorpho(MORPHO_MAINNET);
        // empty data
        bytes memory data = "";
        // mint USD0
        vm.prank(USUAL_MULTISIG_MAINNET);
        IRegistryAccess(REGISTRY_ACCESS_MAINNET).grantRole(keccak256("ALLOWLISTED"), alice);
        vm.prank(DAO_COLLATERAL_MAINNET);
        USD0.mint(alice, amountUSD0PP);
        // approve to mint usd0pp
        vm.startPrank(alice);
        IERC20(address(USD0)).approve(address(usd0PP), amountUSD0PP);
        usd0PP.mint(amountUSD0PP);
        // allow usdc
        IERC20(address(usd0PP)).approve(MORPHO_MAINNET, amountUSD0PP);
        // expect SupplyCollateral event
        vm.expectEmit(true, true, true, true);
        //  Id indexed id, address indexed caller, address indexed onBehalf, uint256 assets
        emit SupplyCollateral(id, alice, alice, amountUSD0PP);
        // supply usdC to the market
        morpho.supplyCollateral(marketParams, amountUSD0PP, alice, data);
        vm.stopPrank();
    }
    // withdraw

    function testSupplyCollateralShouldWork(uint256 amountUSD0PP) public {
        amountUSD0PP = bound(amountUSD0PP, 1, (type(uint128).max));
        testMarketCreationShouldWork();
        IMorpho morpho = IMorpho(MORPHO_MAINNET);
        _supplyCollateral(amountUSD0PP);
        // check position
        Position memory position = morpho.position(id, alice);
        assertEq(position.supplyShares, 0);
        assertEq(position.borrowShares, 0);
        assertEq(position.collateral, amountUSD0PP);
    }

    function testWithdrawCollateralShouldWork(uint256 amountUSD0PP) public {
        amountUSD0PP = bound(amountUSD0PP, 1, (type(uint128).max));
        testSupplyCollateralShouldWork(amountUSD0PP);
        IMorpho morpho = IMorpho(MORPHO_MAINNET);
        Position memory position = morpho.position(id, alice);
        uint256 collateralBefore = position.collateral;
        assertEq(collateralBefore, amountUSD0PP);

        uint256 usd0BalanceBefore = IERC20(usd0PP).balanceOf(alice);
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(alice);
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit WithdrawCollateral(id, alice, alice, alice, amountUSD0PP);
        morpho.withdrawCollateral(marketParams, amountUSD0PP, alice, alice);
        vm.stopPrank();
        // check position
        position = morpho.position(id, alice);
        assertEq(position.supplyShares, 0);
        assertEq(position.borrowShares, 0);
        assertEq(position.collateral, 0);
        uint256 usd0BalanceAfter = IERC20(usd0PP).balanceOf(alice);
        assertEq(usd0BalanceAfter, usd0BalanceBefore + amountUSD0PP);
        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(alice);
        assertEq(usdcBalanceAfter, usdcBalanceBefore);
    }

    function testSupplyOnlyAssetsBorrowShouldNotWork() public {
        uint256 amountUSDC = 1_000_000_000_000;
        testSupplyAssetsShouldWork(amountUSDC);
        IMorpho morpho = IMorpho(MORPHO_MAINNET);
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(bob);
        vm.startPrank(bob);
        // Either assets or shares should be zero.
        // If assets > 0, the system calculates the corresponding shares.
        // If shares > 0, the system calculates the corresponding assets. Similarly, when borrowing, repaying or withdrawing from a market (see the respective function in Morpho.sol).
        vm.expectRevert("insufficient collateral");
        morpho.borrow(marketParams, 1, 0, bob, bob);
        vm.stopPrank();
        // check position
        Position memory position = morpho.position(id, bob);
        assertEq(position.borrowShares, 0);
        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(bob);
        assertEq(usdcBalanceAfter, usdcBalanceBefore);
    }

    function testSupplyCollateralBorrowShouldNotWorkIfNoLiquidity() public {
        uint256 amountUSD0pp = 1_000_000 ether;
        testSupplyCollateralShouldWork(amountUSD0pp);
        IMorpho morpho = IMorpho(MORPHO_MAINNET);
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(alice);
        uint256 usd0BalanceBefore = IERC20(usd0PP).balanceOf(alice);
        vm.startPrank(alice);
        // Either assets or shares should be zero.
        // If assets > 0, the system calculates the corresponding shares.
        // If shares > 0, the system calculates the corresponding assets. Similarly, when borrowing, repaying or withdrawing from a market (see the respective function in Morpho.sol).
        vm.expectRevert("insufficient liquidity");
        morpho.borrow(marketParams, 1, 0, alice, alice);
        vm.stopPrank();
        // check position
        Position memory position = morpho.position(id, alice);
        assertEq(position.borrowShares, 0);
        uint256 usd0BalanceAfter = IERC20(usd0PP).balanceOf(alice);
        assertEq(usd0BalanceBefore, usd0BalanceAfter);
        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(alice);
        assertEq(usdcBalanceAfter, usdcBalanceBefore);
    }

    function testSupplyCollateralBorrowShouldWork() public {
        uint256 amountUSDC = 1_000_000_000_000;
        // bob supplied USDC
        testSupplyAssetsShouldWork(amountUSDC);
        uint256 amountUSD0pp = 1_000_000 ether;
        // alice supplied USD0pp
        _supplyCollateral(amountUSD0pp);
        IMorpho morpho = IMorpho(MORPHO_MAINNET);
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(alice);
        uint256 usd0ppBalanceBefore = IERC20(usd0PP).balanceOf(alice);
        // borrow max usdc at 98% LLTV
        uint256 amountBorrow = amountUSD0pp * marketParams.lltv / 1e18 / 1e12;
        // check position
        Position memory position = morpho.position(id, alice);

        // Either assets or shares should be zero.
        // If assets > 0, the system calculates the corresponding shares.
        // If shares > 0, the system calculates the corresponding assets. Similarly, when borrowing, repaying or withdrawing from a market (see the respective function in Morpho.sol).
        vm.prank(alice);
        morpho.borrow(marketParams, amountBorrow, 0, alice, alice);
        // check position
        position = morpho.position(id, alice);

        assertEq(position.borrowShares, amountBorrow * 1e6);
        uint256 usd0ppBalanceAfter = IERC20(usd0PP).balanceOf(alice);
        assertEq(usd0ppBalanceBefore, usd0ppBalanceAfter);
        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(alice);
        assertEq(usdcBalanceAfter - usdcBalanceBefore, amountBorrow);
    }

    function testLiquidationShouldWork() public {
        // bob supplied USDC
        // alice supplied USD0pp and borrowed USDC
        testSupplyCollateralBorrowShouldWork();
        IMorpho morpho = IMorpho(MORPHO_MAINNET);

        uint256 usd0ppBalanceBefore = IERC20(usd0PP).balanceOf(alice);
        assertEq(usd0ppBalanceBefore, 0);

        Position memory position = morpho.position(id, alice);
        uint256 collateralBefore = 1_000_000 ether;
        assertEq(position.collateral, collateralBefore);
        uint256 usdcAmountLoaned = position.borrowShares / 1e6;

        vm.expectRevert("position is healthy");
        morpho.liquidate(marketParams, alice, 0, position.borrowShares, "");
        // update chainlink oracle price with vm.mock latest price
        IOracle oracle = IOracle(MORPHO_CHAINLINK_ORACLE_USDC_SDAI);

        uint256 answer = oracle.price();
        // -0.11$ to make the position unhealthy
        answer -= 110_000_000_000_000_000_000_000;
        vm.mockCall(
            MORPHO_CHAINLINK_ORACLE_USDC_SDAI,
            abi.encodeWithSelector(IOracle.price.selector),
            abi.encode(answer)
        );
        // bob needs to be allowlisted to receive USD0
        vm.prank(USUAL_MULTISIG_MAINNET);
        IRegistryAccess(REGISTRY_ACCESS_MAINNET).grantRole(keccak256("ALLOWLISTED"), bob);
        // bob needs USDC to liquidate
        deal(USDC, bob, usdcAmountLoaned);
        deal(address(usd0PP), bob, 0);
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(bob);
        assertEq(usdcBalanceBefore, usdcAmountLoaned);
        vm.startPrank(bob);
        // allow usdc
        IERC20(USDC).approve(MORPHO_MAINNET, usdcAmountLoaned);
        // liquidate all shares
        vm.expectEmit(true, true, true, false);
        emit Liquidate(id, bob, alice, 0, 0, 0, 0, 0);
        morpho.liquidate(marketParams, alice, 0, position.borrowShares, "");
        vm.stopPrank();
        // check position
        position = morpho.position(id, alice);
        // collateral is now less because the price has changed and the position is unhealthy
        uint256 collateralAfter = position.collateral;
        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(bob);
        // all usdc have been used to liquidate
        assertEq(usdcBalanceAfter, 0);
        uint256 usd0ppBalanceAfter = IERC20(usd0PP).balanceOf(bob);

        // we got back the collateral
        assertEq(usd0ppBalanceAfter, collateralBefore - collateralAfter);
        // which is > 98% of the collateral locked in the position
        assertGt(usd0ppBalanceAfter, (collateralBefore * 98) / 100);
    }
}
