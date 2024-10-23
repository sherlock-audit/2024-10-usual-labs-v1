// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {ERC4626Test} from "./ERC4626.test.sol";
import {SetupTest} from "../setup.t.sol";

import {ERC20, IERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC4626, ERC20, IERC20} from "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {UsualX} from "../../src/vaults/UsualX.sol";
import {ONE_MONTH_IN_SECONDS} from "src/mock/constants.sol";
import {
    CONTRACT_USUALX,
    CONTRACT_USUAL,
    USUALSymbol,
    USUALName,
    USUALXSymbol,
    USUALXName,
    USUALX_WITHDRAW_FEE,
    WITHDRAW_FEE_UPDATER_ROLE,
    YIELD_PRECISION
} from "src/constants.sol";

interface IMockERC20 is IERC20 {
    function mint(address to, uint256 value) external;

    function burn(address from, uint256 value) external;
}

contract UsualXUnitTest is ERC4626Test, SetupTest {
    error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 shares);

    function setUp() public override(ERC4626Test, SetupTest) {
        SetupTest.setUp();
        usualX = new UsualX();
        usual = address(new ERC20Mock());
        vm.startPrank(admin);
        registryContract.setContract(CONTRACT_USUAL, usual);
        _resetInitializerImplementation(address(usualX));
        usualX.initialize(address(registryContract), 0, USUALXName, USUALXSymbol);
        registryContract.setContract(CONTRACT_USUALX, address(usualX));

        vm.stopPrank();
        _underlying_ = usual;
        _vault_ = address(usualX);
        _delta_ = 0;
        _vaultMayBeEmpty = false;
        _unlimitedAmount = false;
    }

    function clamp(Init memory init) internal view returns (Init memory) {
        init.user[2] = admin;
        init.user[1] = bob;
        init.user[0] = alice;
        uint256 max = type(uint120).max;
        uint256 min = 100;
        for (uint256 i = 0; i < N; i++) {
            init.share[i] = init.share[i] % max + min;
            init.asset[i] = init.asset[i] % max + min;
        }
        init.yield = 0e18;
        return init;
    }

    function setUpVault(Init memory init) public override {
        // setup initial shares and assets for individual users
        for (uint256 i = 0; i < N; i++) {
            address user = init.user[i];
            // shares
            uint256 shares = init.share[i];
            IMockERC20(_underlying_).mint(user, shares);
            _approve(_underlying_, user, _vault_, shares);
            vm.prank(user);
            IERC4626(_vault_).deposit(shares, user);
            uint256 assets = init.asset[i];
            IMockERC20(_underlying_).mint(user, assets);
        }
    }

    function test_mint(Init memory init, uint256 shares, uint256 allowance) public override {
        init = clamp(init);
        uint256 assetsRequired = IERC4626(_vault_).previewMint(shares);
        allowance = bound(allowance, assetsRequired, type(uint256).max);
        super.test_mint(init, shares, allowance);
    }

    function test_RT_deposit_withdraw(Init memory init, uint256 assets) public override {
        init = clamp(init);
        super.test_RT_deposit_withdraw(init, assets);
    }

    function test_redeem(Init memory init, uint256 shares, uint256 allowance) public override {
        init = clamp(init);
        allowance = bound(allowance, shares, type(uint256).max);
        super.test_redeem(init, shares, shares);
    }

    function test_deposit(Init memory init, uint256 assets, uint256 allowance) public override {
        init = clamp(init);
        allowance = bound(allowance, assets, type(uint256).max);
        super.test_deposit(init, assets, allowance);
    }

    function test_RT_withdraw_mint(Init memory init, uint256 assets) public override {
        init = clamp(init);
        super.test_RT_withdraw_mint(init, assets);
    }

    function test_RT_withdraw_deposit(Init memory init, uint256 assets) public override {
        init = clamp(init);
        super.test_RT_withdraw_deposit(init, assets);
    }

    function test_RT_redeem_mint(Init memory init, uint256 shares) public override {
        init = clamp(init);
        super.test_RT_redeem_mint(init, shares);
    }

    //TODO: test_RT_mint_withdraw
    function test_RT_mint_withdraw(Init memory init, uint256 shares) public override {
        init = clamp(init);
        super.test_RT_mint_withdraw(init, shares);
    }

    function test_RT_deposit_redeem(Init memory init, uint256 assets) public override {
        init = clamp(init);
        super.test_RT_deposit_redeem(init, assets);
    }

    function test_RT_redeem_deposit(Init memory init, uint256 shares) public override {
        init = clamp(init);
        super.test_RT_redeem_deposit(init, shares);
    }

    function test_RT_mint_redeem(Init memory init, uint256 shares) public override {
        init = clamp(init);
        super.test_RT_mint_redeem(init, shares);
    }

    function test_totalAssets(Init memory init) public override {
        init = clamp(init);
        super.test_totalAssets(init);
    }

    function test_previewWithdraw(Init memory init, uint256 assets) public override {
        init = clamp(init);
        super.test_previewWithdraw(init, assets);
    }

    function test_previewRedeem(Init memory init, uint256 shares) public override {
        init = clamp(init);
        super.test_previewRedeem(init, shares);
    }

    function test_previewMint(Init memory init, uint256 shares) public override {
        init = clamp(init);
        super.test_previewMint(init, shares);
    }

    function test_previewDeposit(Init memory init, uint256 assets) public override {
        init = clamp(init);
        super.test_previewDeposit(init, assets);
    }

    function test_maxMint(Init memory init) public override {
        init = clamp(init);
        super.test_maxMint(init);
    }

    function test_maxDeposit(Init memory init) public override {
        init = clamp(init);
        super.test_maxDeposit(init);
    }

    function test_convertToShares(Init memory init, uint256 assets) public override {
        init = clamp(init);
        super.test_convertToShares(init, assets);
    }

    function test_convertToAssets(Init memory init, uint256 shares) public override {
        init = clamp(init);
        super.test_convertToAssets(init, shares);
    }

    function test_asset(Init memory init) public override {
        init = clamp(init);
        super.test_asset(init);
    }

    function test_withdraw(Init memory init, uint256 assets) public {
        init = clamp(init);
        setUpVault(init);
        address receiver = init.user[1];
        address owner = init.user[2];
        uint256 oldReceiverAsset = IERC20(_underlying_).balanceOf(receiver);
        uint256 oldOwnerShare = IERC20(_vault_).balanceOf(owner);

        assets = bound(assets, 100, _max_withdraw(owner));
        _approve(_underlying_, owner, _vault_, type(uint256).max);

        vm.prank(owner);
        uint256 shares = vault_withdraw(assets, owner, owner);

        uint256 newReceiverAsset = IERC20(_underlying_).balanceOf(receiver);
        uint256 newOwnerShare = IERC20(_vault_).balanceOf(owner);

        assertApproxGeAbs(oldReceiverAsset, newReceiverAsset, _delta_); // NOTE: this may fail if the receiver is a contract in which the asset is stored
        assertApproxEqAbs(newOwnerShare + shares, oldOwnerShare, _delta_, "share");
    }

    function test_maxWithdraw(Init memory init) public override {
        init = clamp(init);
        super.test_maxWithdraw(init);
    }

    function test_maxRedeem(Init memory init) public override {
        init = clamp(init);
        super.test_maxRedeem(init);
    }

    function testFail_redeem(Init memory init, uint256 shares) public override {
        init = clamp(init);
        super.testFail_redeem(init, shares);
    }

    function testFail_withdraw(Init memory init, uint256 assets) public override {
        init = clamp(init);
        super.testFail_withdraw(init, assets);
    }

    function test_poc_withdraw_yield_revert() public {
        uint256 fee = 500; // 5%
        vm.prank(admin);
        registryAccess.grantRole(WITHDRAW_FEE_UPDATER_ROLE, address(this));
        usualX.updateWithdrawFee(fee);

        uint256 depositAmount = 1e18;
        uint256 yieldAmount = 100e18;
        deal(address(usual), address(alice), depositAmount);
        deal(address(usual), address(usualX), yieldAmount);

        // A yield distribution is started
        vm.prank(address(distributionModule));
        usualX.startYieldDistribution(100e18, block.timestamp, block.timestamp + 1 days);

        // Alice deposits
        vm.startPrank(alice);
        ERC20Mock(usual).approve(address(usualX), depositAmount);
        usualX.deposit(depositAmount, alice);

        skip(1 days);

        // Alice should be able to withdraw
        uint256 maxWithdraw = usualX.maxWithdraw(alice);
        usualX.withdraw(maxWithdraw, alice, alice);
    }

    function testWithdrawNotAvoidFees() public {
        uint256 fee = 100; // 1%
        vm.prank(admin);
        registryAccess.grantRole(WITHDRAW_FEE_UPDATER_ROLE, address(this));
        usualX.updateWithdrawFee(fee);

        uint256 depositAmount = 10_000;

        vm.startPrank(alice);
        ERC20Mock(usual).mint(alice, depositAmount);
        ERC20Mock(usual).approve(address(usualX), depositAmount);
        usualX.deposit(depositAmount, alice);

        uint256 snap = vm.snapshot();

        // Scenario 1:
        // Alice redeems all her shares using `redeem()`
        uint256 redeemShares = usualX.maxRedeem(alice);
        assertEq(redeemShares, depositAmount);
        uint256 redeemAssets = usualX.redeem(redeemShares, alice, alice);
        assertEq(redeemAssets, depositAmount - fee);
        // Effective fee on assets (1%):
        assertEq(ERC20(usual).balanceOf(alice), 9900);

        // Try again using many small withdrawals
        vm.revertTo(snap);

        // Scenario 2:
        // Alice redeems all her shares in many small withdrawals
        for (uint256 i; i < 100; i++) {
            usualX.withdraw(fee - 1, alice, alice);
        }
        // Should fail because of the withdrawal fee
        vm.expectRevert(abi.encodeWithSelector(ERC4626ExceededMaxWithdraw.selector, alice, 1, 0));
        usualX.withdraw(1, alice, alice);

        // Effective fee on assets (1%):
        assertEq(ERC20(usual).balanceOf(alice), 9900);
    }

    function test_poc_withdraw_redeem_fee_equivalence() public {
        uint256 fee = 500; // 5%
        vm.prank(admin);
        registryAccess.grantRole(WITHDRAW_FEE_UPDATER_ROLE, address(this));
        usualX.updateWithdrawFee(fee);

        uint256 depositAmount = 100e18;

        vm.startPrank(alice);
        ERC20Mock(usual).mint(alice, depositAmount);
        ERC20Mock(usual).approve(address(usualX), depositAmount);
        usualX.deposit(depositAmount, alice);

        uint256 snap = vm.snapshot();

        // Scenario 1: Alice redeems all her shares using `redeem()`
        uint256 redeemShares = usualX.maxRedeem(alice);
        usualX.redeem(redeemShares, alice, alice);
        assertEq(usualX.balanceOf(alice), 0);
        assertEq(ERC20(usual).balanceOf(alice), 95e18); // 5% fee

        // Scenario 2: Alice redeems all her shares using `withdraw()`
        vm.revertTo(snap);
        uint256 withdrawAssets = usualX.maxWithdraw(alice);
        uint256 withdrawShares = usualX.withdraw(withdrawAssets, alice, alice);
        assertEq(ERC20(usual).balanceOf(alice), 95e18); // 5% fee
        assertEq(usualX.balanceOf(alice), 0);

        // Alice can further withdraw assets beyond her limit
        for (uint256 i; i < 100; i++) {
            withdrawAssets = usualX.maxWithdraw(alice);
            withdrawShares = usualX.withdraw(withdrawAssets, alice, alice);
        }
        assertEq(ERC20(usual).balanceOf(alice), 95e18); // Should also be 5% fee
    }

    function testGetYieldRate(uint256 yieldAmount) public {
        yieldAmount = bound(yieldAmount, 1e18, 100e18);

        deal(address(usualToken), address(distributionModule), yieldAmount);
        deal(address(usual), address(usualX), yieldAmount);

        uint256 expectedYieldRate = yieldAmount * YIELD_PRECISION / 1 days;
        // A yield distribution is started
        vm.prank(address(distributionModule));
        usualX.startYieldDistribution(yieldAmount, block.timestamp, block.timestamp + 1 days);
        assertEq(usualX.getYieldRate(), expectedYieldRate);
    }
}
