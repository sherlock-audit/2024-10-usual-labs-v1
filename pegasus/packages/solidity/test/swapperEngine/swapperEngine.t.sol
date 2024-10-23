// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.20;

import {SetupTest} from "../setup.t.sol";
import {Pausable} from "openzeppelin-contracts/utils/Pausable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {RwaMock} from "src/mock/rwaMock.sol";
import {SwapperEngine} from "src/swapperEngine/SwapperEngine.sol";
import {IUSDC} from "test/interfaces/IUSDC.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {Normalize} from "src/utils/normalize.sol";
import {SigUtils} from "test/utils/sigUtils.sol";

import {
    SWAPPER_ENGINE,
    CONTRACT_SWAPPER_ENGINE,
    CONTRACT_USDC,
    MINIMUM_USDC_PROVIDED,
    DEFAULT_ADMIN_ROLE
} from "src/constants.sol";
import {NotAuthorized} from "src/errors.sol";
import {USDC, USDT} from "src/mock/constants.sol";
import {
    TokenNotWhitelist,
    AmountTooLow,
    SameValue,
    NullContract,
    NoOrdersIdsProvided
} from "src/errors.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {
    TokenNotWhitelist,
    SameValue,
    NullContract,
    InsufficientUSD0Balance,
    USDCAmountNotFullyMatched,
    OrderNotActive,
    NotRequester,
    InsufficientUSD0Allowance,
    AmountTooLow,
    AmountIsZero
} from "src/errors.sol";

contract SwapperEngineTest is SetupTest {
    using SafeERC20 for IERC20;
    using Normalize for uint256;

    RwaMock public rwa$;
    RwaMock public rwa2;

    event Deposit(address indexed requester, uint256 indexed orderId, uint256 amount);
    event Withdraw(address indexed requester, uint256 indexed orderId, uint256 amount);
    event OrderMatched(
        address indexed usdcProviderAddr,
        address indexed usd0Provider,
        uint256 indexed orderId,
        uint256 amount
    );
    event Initialized(uint64);

    /*//////////////////////////////////////////////////////////////
                            1. SETUP & HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Set up the test environment
    /// - Create a fork of the Ethereum mainnet and select it
    /// - Call the parent contract's setUp function
    /// - Label the USDC and USDT token addresses
    /// - Create a new RWA token (rwa$) and label its address
    /// - Set up USDC in the registryContract and registryAccess
    /// - Deploy a new SwapperEngine contract, reset its initializer, and initialize it
    /// - Set the SwapperEngine contract in the registryContract and grant it necessary roles
    /// - Whitelist the RWA token for various addresses
    /// - Add the RWA token to the tokenMapping, link it to the STBC token, and set up a bucket
    /// - Set the oracle prices for the RWA token, USDT, and USDC
    function setUp() public override {
        uint256 forkId = vm.createFork("eth");
        vm.selectFork(forkId);
        super.setUp();
        vm.label(address(USDC), "USDC"); //uses mainnet fork to set up USDC contract
        vm.label(address(USDT), "USDT");

        vm.startPrank(admin);
        rwa$ = RwaMock(rwaFactory.createRwa("Hashnote RWA Dollar", "RWA$", 6));
        vm.label(address(rwa$), "rwa$");

        // Setup SwapperEngine
        swapperEngine = new SwapperEngine();
        _resetInitializerImplementation(address(swapperEngine));
        swapperEngine.initialize(address(registryContract));
        registryContract.setContract(CONTRACT_SWAPPER_ENGINE, address(swapperEngine));
        registryAccess.grantRole(SWAPPER_ENGINE, address(swapperEngine));

        vm.stopPrank();

        _whitelistRWA(address(rwa$), address(swapperEngine));
        _whitelistRWA(address(rwa$), alice);
        _whitelistRWA(address(rwa$), bob);
        _whitelistRWA(address(rwa$), treasury);
        _whitelistRWA(address(rwa$), address(daoCollateral));

        vm.prank(admin);
        tokenMapping.addUsd0Rwa(address(rwa$));
        _linkSTBCToRwa(rwa$);
        whitelistPublisher(address(rwa$), address(stbcToken));

        _setupBucket(address(rwa$), address(stbcToken));
        _setOraclePrice(address(rwa$), 1e6);
        _setOraclePrice(address(USDT), 1e6);
        _setOraclePrice(address(USDC), 1e6);
    }

    function _getUsdcWadPrice() private view returns (uint256) {
        return classicalOracle.getPrice(USDC);
    }

    function _getUsd0WadEquivalent(uint256 usdcTokenAmountInNativeDecimals, uint256 usdcWadPrice)
        private
        view
        returns (uint256 usd0WadEquivalent)
    {
        uint8 decimals = IERC20Metadata(USDC).decimals();
        uint256 usdcWad = usdcTokenAmountInNativeDecimals.tokenAmountToWad(decimals);
        usd0WadEquivalent = usdcWad.wadAmountByPrice(usdcWadPrice);
    }

    function _getUsdcAmountFromUsd0WadEquivalent(uint256 usd0WadAmount, uint256 usdcWadPrice)
        private
        view
        returns (uint256 usdcTokenAmountInNativeDecimals)
    {
        uint8 decimals = IERC20Metadata(USDC).decimals();
        usdcTokenAmountInNativeDecimals =
            usd0WadAmount.wadTokenAmountForPrice(usdcWadPrice, decimals);
    }

    function _dealUSDCAndApprove(uint256 amount, address owner) public {
        deal(address(USDC), owner, amount);
        vm.prank(owner);
        IUSDC(address(USDC)).approve(address(swapperEngine), amount);
    }

    function _dealUSDCAndApproveAndDeposit(uint256 amount, address owner) public {
        deal(address(USDC), owner, amount);
        vm.startPrank(owner);
        IUSDC(address(USDC)).approve(address(swapperEngine), amount);
        swapperEngine.depositUSDC(amount);
        vm.stopPrank();
    }

    function _dealStbcAndApprove(uint256 amount, address owner) public {
        deal(address(stbcToken), owner, amount);
        vm.prank(owner);
        IERC20(address(stbcToken)).approve(address(swapperEngine), amount);
    }

    function _createMultipleDepositOrders(
        uint256 amountPerOrder,
        uint256 numOrders,
        uint256 amountToTake
    ) public returns (uint256[] memory, uint256, uint256) {
        for (uint256 i = 0; i < numOrders; i++) {
            _dealUSDCAndApproveAndDeposit(amountPerOrder, alice);
        }

        uint256[] memory orderIdsToTake = new uint256[](numOrders);
        for (uint256 i = 0; i < numOrders; i++) {
            orderIdsToTake[i] = i + 1;
        }

        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 expectedUsd0Amount = _getUsd0WadEquivalent(amountToTake, usdcWadPrice);

        return (orderIdsToTake, usdcWadPrice, expectedUsd0Amount);
    }

    function testTokenConversionFunctions() public {
        // Test case 1: USDC price is 1 USD per USDC (1e6)
        _setOraclePrice(address(USDC), 1e6);
        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 usd0Amount = 1000e18; // 1000 USD0
        uint256 expectedUsdcAmount = 1000e6; // 1000 USDC

        uint256 usdcAmount = _getUsdcAmountFromUsd0WadEquivalent(usd0Amount, usdcWadPrice);
        assertEq(usdcAmount, expectedUsdcAmount);

        uint256 convertedUsd0Amount = _getUsd0WadEquivalent(usdcAmount, usdcWadPrice);
        assertEq(convertedUsd0Amount, usd0Amount);

        // Test case 2: USDC price is 0.5 USD per USDC (5e5)
        _setOraclePrice(address(USDC), 5e5);
        usdcWadPrice = _getUsdcWadPrice();
        usd0Amount = 1000e18; // 1000 USD0
        expectedUsdcAmount = 2000e6; // 2000 USDC

        convertedUsd0Amount = _getUsd0WadEquivalent(expectedUsdcAmount, usdcWadPrice);
        assertEq(convertedUsd0Amount, usd0Amount);

        usdcAmount = _getUsdcAmountFromUsd0WadEquivalent(usd0Amount, usdcWadPrice);
        assertEq(usdcAmount, expectedUsdcAmount);

        // Test case 3: USDC price is 2 USD per USDC (2e6)
        _setOraclePrice(address(USDC), 2e6);
        usdcWadPrice = _getUsdcWadPrice();
        usd0Amount = 1000e18; // 1000 USD0
        expectedUsdcAmount = 500e6; // 500 USDC

        usdcAmount = _getUsdcAmountFromUsd0WadEquivalent(usd0Amount, usdcWadPrice);
        assertEq(usdcAmount, expectedUsdcAmount);

        convertedUsd0Amount = _getUsd0WadEquivalent(usdcAmount, usdcWadPrice);
        assertEq(convertedUsd0Amount, usd0Amount);

        // Test case 4: USDC price is 0.1 USD per USDC (1e5)
        _setOraclePrice(address(USDC), 1e5);
        usdcWadPrice = _getUsdcWadPrice();
        usd0Amount = 1000e18; // 1000 USD0
        expectedUsdcAmount = 10_000e6; // 10000 USDC

        usdcAmount = _getUsdcAmountFromUsd0WadEquivalent(usd0Amount, usdcWadPrice);
        assertEq(usdcAmount, expectedUsdcAmount);

        convertedUsd0Amount = _getUsd0WadEquivalent(usdcAmount, usdcWadPrice);
        assertEq(convertedUsd0Amount, usd0Amount);

        // Test case 5: USDC price is 10 USD per USDC (1e7)
        _setOraclePrice(address(USDC), 1e7);
        usdcWadPrice = _getUsdcWadPrice();
        usd0Amount = 1000e18; // 1000 USD0
        expectedUsdcAmount = 100e6; // 100 USDC

        usdcAmount = _getUsdcAmountFromUsd0WadEquivalent(usd0Amount, usdcWadPrice);
        assertEq(usdcAmount, expectedUsdcAmount);

        convertedUsd0Amount = _getUsd0WadEquivalent(usdcAmount, usdcWadPrice);
        assertEq(convertedUsd0Amount, usd0Amount);
    }

    function testAdminIsSet() public view {
        assertTrue(registryAccess.hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

    /// @dev Test case for checking that sum of mulDiv is not the same as mulDiv of the sum if we round down
    /// Verifies that the two are not equal
    function testUsd0ConversionPrecision(uint256 rawX, uint256 rawY, uint256 rawOraclePrice)
        public
    {
        uint256 oraclePrice = bound(rawOraclePrice, 1, 100e18); // Ensure oracle price is within a reasonable range
        _setOraclePrice(address(USDC), oraclePrice);

        uint256 x = bound(rawX, MINIMUM_USDC_PROVIDED + 1, type(uint128).max);
        uint256 y = bound(rawY, MINIMUM_USDC_PROVIDED + 1, type(uint128).max);
        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 a = _getUsd0WadEquivalent(x, usdcWadPrice) + _getUsd0WadEquivalent(y, usdcWadPrice);
        uint256 b = _getUsd0WadEquivalent(x + y, usdcWadPrice);
        assertEq(a, b);
    }

    function testUsdcConversionPrecision(uint256 rawX, uint256 rawY, uint256 rawOraclePrice)
        public
    {
        uint256 oraclePrice = bound(rawOraclePrice, 1e16, 5e18); // Ensure oracle price is within a reasonable range
        _setOraclePrice(address(USDC), oraclePrice);

        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 z = bound(
            rawX, _getUsd0WadEquivalent(MINIMUM_USDC_PROVIDED + 1, usdcWadPrice), type(uint128).max
        );
        uint256 w = bound(
            rawY, _getUsd0WadEquivalent(MINIMUM_USDC_PROVIDED + 1, usdcWadPrice), type(uint128).max
        );

        // check the two amounts don't over flow a uint256
        assert(z <= type(uint256).max);
        assert(w <= type(uint256).max);

        uint256 c = _getUsdcAmountFromUsd0WadEquivalent(z, usdcWadPrice)
            + _getUsdcAmountFromUsd0WadEquivalent(w, usdcWadPrice);
        uint256 d = _getUsdcAmountFromUsd0WadEquivalent(z + w, usdcWadPrice);

        if (d - c == 0) {
            assert(c == d);
        } else {
            assert(d - c == 1);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            2. INITIALIZE
    //////////////////////////////////////////////////////////////*/
    // 2.1 Testing revert properties //
    function testInitializeSwapperEngineShouldFailWithNullContract() public {
        _resetInitializerImplementation(address(swapperEngine));
        vm.expectRevert(abi.encodeWithSelector(NullContract.selector));
        swapperEngine.initialize(address(0));
    }

    // 2.2 Testing basic flows //
    function testConstructorSwapper() public {
        vm.expectEmit();
        emit Initialized(type(uint64).max);

        SwapperEngine engine = new SwapperEngine();
        assertTrue(address(engine) != address(0));
    }
    /*//////////////////////////////////////////////////////////////
                    3. UPDATE_MINIMUM_USDC_PROVIDED
    //////////////////////////////////////////////////////////////*/
    // 3.1 Testing revert properties //

    function testUpdateMinimumUSDCAmountProvidedOnlyAdmin() public {
        uint256 newMinimumAmount = 100e6;

        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        vm.prank(alice);
        swapperEngine.updateMinimumUSDCAmountProvided(newMinimumAmount);
    }

    function testUpdateMinimumUSDCAmountProvidedBelowOneUSDC() public {
        uint256 newMinimumAmount = 1e6 - 1;

        // Minimum amount must be greater than 1 USDC
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AmountTooLow.selector));
        swapperEngine.updateMinimumUSDCAmountProvided(newMinimumAmount);
    }

    // 3.2 Testing basic flows //
    function testCheckMinimumUSDCForOrder() public view {
        uint256 minUSDC = swapperEngine.minimumUSDCAmountProvided();
        assertEq(minUSDC, MINIMUM_USDC_PROVIDED);
    }

    function testUpdateMinimumUSDCAmountProvided() public {
        uint256 newMinimumAmount = 100e6;

        vm.prank(admin);
        swapperEngine.updateMinimumUSDCAmountProvided(newMinimumAmount);

        assertEq(swapperEngine.minimumUSDCAmountProvided(), newMinimumAmount);
    }

    function testUpdateMinimumUSDCAmountProvidedJustAboveOneUSDC() public {
        uint256 newMinimumAmount = 1e6 + 1;

        vm.prank(admin);
        swapperEngine.updateMinimumUSDCAmountProvided(newMinimumAmount);

        assertEq(swapperEngine.minimumUSDCAmountProvided(), newMinimumAmount);
    }

    function testUpdateMinimumUSDCAmountProvidedSameValue() public {
        uint256 currentMinimumAmount = swapperEngine.minimumUSDCAmountProvided();

        vm.prank(admin);
        swapperEngine.updateMinimumUSDCAmountProvided(currentMinimumAmount);

        assertEq(swapperEngine.minimumUSDCAmountProvided(), currentMinimumAmount);
    }

    function testUpdateMinimumUSDCAmountProvidedMultipleTimes() public {
        uint256 newMinimumAmount1 = 5e6;
        uint256 newMinimumAmount2 = 10e6;

        vm.startPrank(admin);
        swapperEngine.updateMinimumUSDCAmountProvided(newMinimumAmount1);
        assertEq(swapperEngine.minimumUSDCAmountProvided(), newMinimumAmount1);

        swapperEngine.updateMinimumUSDCAmountProvided(newMinimumAmount2);
        assertEq(swapperEngine.minimumUSDCAmountProvided(), newMinimumAmount2);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           4. PAUSE & UNPAUSE
    //////////////////////////////////////////////////////////////*/

    function testUnpause() public {
        vm.prank(pauser);
        swapperEngine.pause();
        assertTrue(swapperEngine.paused());

        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        swapperEngine.unpause();

        vm.prank(admin);
        swapperEngine.unpause();

        assertFalse(swapperEngine.paused());
    }

    /*//////////////////////////////////////////////////////////////
                5. DEPOSIT_USDC & DEPOSIT_USDC_WITH_PERMIT
    //////////////////////////////////////////////////////////////*/
    // 5.1 Testing revert properties //
    function testDepositUSDCShouldFailIfBlacklistedButPassEvenIfNotAllowlisted() public {
        uint256 amountToDeposit = MINIMUM_USDC_PROVIDED + 1;
        _dealUSDCAndApprove(amountToDeposit, alice);

        vm.prank(alice);
        // vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        swapperEngine.depositUSDC(amountToDeposit);

        vm.startPrank(blacklistOperator);
        // registryAccess.grantRole(ALLOWLISTED, address(alice));
        stbcToken.blacklist(address(alice));
        vm.stopPrank();

        _dealUSDCAndApprove(amountToDeposit, alice);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        swapperEngine.depositUSDC(amountToDeposit);
        vm.stopPrank();
    }

    function testDepositUSDCShouldFailWhenPaused() public {
        uint256 amountToDeposit = MINIMUM_USDC_PROVIDED + 1;
        _dealUSDCAndApprove(amountToDeposit, alice);

        vm.prank(pauser);
        swapperEngine.pause();
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(alice);

        swapperEngine.depositUSDC(amountToDeposit);
        vm.stopPrank();
    }

    function testDepositUSDCWithPermitBelowOneUSDCAfterMinimumAmountUpdate() public {
        uint256 newMinimumAmount = 2e6;

        vm.prank(admin);
        swapperEngine.updateMinimumUSDCAmountProvided(newMinimumAmount);

        uint256 amountToDeposit = 1e6;

        vm.startPrank(alice);
        // Amount must be greater than MINIMUM_USDC_PROVIDED
        vm.expectRevert(abi.encodeWithSelector(AmountTooLow.selector));
        swapperEngine.depositUSDCWithPermit(amountToDeposit, 0, 0, 0, 0);
        vm.stopPrank();
    }

    /// @dev Test case for depositing USDC with an insufficient balance.
    ///
    /// This test expects the transaction to revert since the depositor
    /// does not have enough USDC tokens to complete the deposit.
    function testDepositUSDCWithInsufficientBalance() public {
        uint256 amountToDeposit = MINIMUM_USDC_PROVIDED;
        _dealUSDCAndApprove(amountToDeposit - 1, alice);

        vm.startPrank(alice);
        IUSDC(address(USDC)).approve(address(swapperEngine), amountToDeposit);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        swapperEngine.depositUSDC(amountToDeposit);
        vm.stopPrank();
    }

    function testDepositUSDCBelowOneUSDCAfterMinimumAmountUpdate() public {
        uint256 newMinimumAmount = 2e6;

        vm.prank(admin);
        swapperEngine.updateMinimumUSDCAmountProvided(newMinimumAmount);

        uint256 amountToDeposit = 1e6;
        _dealUSDCAndApprove(amountToDeposit, alice);

        // Amount must be greater than MINIMUM_USDC_PROVIDED
        vm.expectRevert(abi.encodeWithSelector(AmountTooLow.selector));
        swapperEngine.depositUSDC(amountToDeposit);
        vm.stopPrank();
    }

    function testDepositUSDCWithPermitFailingERC20Permit() public {
        uint256 amount = MINIMUM_USDC_PROVIDED + 1;
        deal(address(USDC), alice, amount);

        // swap for USD0
        uint256 deadline = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(USDC), alice, alicePrivKey, address(swapperEngine), amount, deadline
        );
        vm.startPrank(alice);

        // deadline in the past
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        swapperEngine.depositUSDCWithPermit(amount, deadline, v, r, s);
        deadline = block.timestamp + 100;

        // insufficient amount
        (v, r, s) = _getSelfPermitData(
            address(USDC), alice, alicePrivKey, address(swapperEngine), amount - 1, deadline
        );
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        swapperEngine.depositUSDCWithPermit(amount, deadline, v, r, s);

        // bad v

        (v, r, s) = _getSelfPermitData(
            address(USDC), alice, alicePrivKey, address(swapperEngine), amount, deadline
        );
        vm.expectRevert("ERC20: transfer amount exceeds allowance");

        swapperEngine.depositUSDCWithPermit(amount, deadline, v + 1, r, s);
        // bad r

        (v, r, s) = _getSelfPermitData(
            address(USDC), alice, alicePrivKey, address(swapperEngine), amount, deadline
        );
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        swapperEngine.depositUSDCWithPermit(amount, deadline, v, keccak256("bad r"), s);

        // bad s
        (v, r, s) = _getSelfPermitData(
            address(USDC), alice, alicePrivKey, address(swapperEngine), amount, deadline
        );
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        swapperEngine.depositUSDCWithPermit(amount, deadline, v, r, keccak256("bad s"));

        //bad nonce
        (v, r, s) = _getSelfPermitData(
            address(USDC),
            alice,
            alicePrivKey,
            address(swapperEngine),
            amount,
            deadline,
            IERC20Permit(address(USDC)).nonces(alice) + 1
        );
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        swapperEngine.depositUSDCWithPermit(amount, deadline, v, r, s);

        //bad spender
        (v, r, s) = _getSelfPermitData(
            address(USDC),
            bob,
            bobPrivKey,
            address(swapperEngine),
            amount,
            deadline,
            IERC20Permit(address(USDC)).nonces(bob)
        );
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        swapperEngine.depositUSDCWithPermit(amount, deadline, v, r, s);
        // this should work
        (v, r, s) = _getSelfPermitData(
            address(USDC), alice, alicePrivKey, address(swapperEngine), amount, deadline
        );
        swapperEngine.depositUSDCWithPermit(amount, deadline, v, r, s);
        assertEq(IUSDC(address(USDC)).balanceOf(address(swapperEngine)), amount);
        vm.stopPrank();
    }

    // 5.2 Testing basic flows //
    function testDepositUSDCWithPermit(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, MINIMUM_USDC_PROVIDED + 1, type(uint128).max);
        deal(address(USDC), alice, amountToDeposit);
        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(USDC), alice, alicePrivKey, address(swapperEngine), amountToDeposit, deadline
        );

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true);
        emit Deposit(alice, 1, amountToDeposit);
        swapperEngine.depositUSDCWithPermit(amountToDeposit, deadline, v, r, s);
        vm.stopPrank();

        assertEq(IUSDC(address(USDC)).balanceOf(address(swapperEngine)), amountToDeposit);
    }

    function testDepositUSDCWithPermitShouldWorkIfPermitAlreadyUsed(uint256 amountToDeposit)
        public
    {
        amountToDeposit = bound(amountToDeposit, MINIMUM_USDC_PROVIDED + 1, type(uint128).max);
        deal(address(USDC), alice, amountToDeposit);
        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(USDC), alice, alicePrivKey, address(swapperEngine), amountToDeposit, deadline
        );

        vm.startPrank(alice);
        // call permit first
        IERC20Permit(address(USDC)).permit(
            alice, address(swapperEngine), amountToDeposit, deadline, v, r, s
        );
        vm.expectEmit(true, true, true, true);
        emit Deposit(alice, 1, amountToDeposit);
        swapperEngine.depositUSDCWithPermit(amountToDeposit, deadline, v, r, s);
        vm.stopPrank();

        assertEq(IUSDC(address(USDC)).balanceOf(address(swapperEngine)), amountToDeposit);
    }

    function testDepositUSDCFuzz(uint256 amount) public {
        // Setup and provide USDC to the test address
        amount = bound(amount, 1, type(uint128).max);
        _dealUSDCAndApprove(amount, alice);
        vm.startPrank(alice);

        if (amount >= MINIMUM_USDC_PROVIDED) {
            // Expect a successful deposit if amount is above the minimum required
            vm.expectEmit(true, true, true, true);
            emit Deposit(alice, 1, amount);
            swapperEngine.depositUSDC(amount);
            assertEq(IUSDC(address(USDC)).balanceOf(address(swapperEngine)), amount);
        } else {
            // Expect a revert if depositing below the minimum amount
            // Amount must be greater than MINIMUM_USDC_PROVIDED
            vm.expectRevert(abi.encodeWithSelector(AmountTooLow.selector));
            swapperEngine.depositUSDC(amount);
        }
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
    6. PROVIDE_USD0_RECEIVE_USDC & PROVIDE_USD0_RECEIVE_USDC_WITH_PERMIT
    //////////////////////////////////////////////////////////////*/
    // 6.1 Testing revert properties //

    /// @dev Test case for providing USD0 to receive USDC when the provider has an insufficient USD0 balance.
    ///
    /// This test creates a specified number of USDC orders with a fixed amount per order. It then attempts to provide USD0 and receive
    /// USDC, but the provider's USD0 balance is set to be 1 token less than the expected amount.
    ///
    /// The test expects the transaction to revert since the provider does not have enough
    /// USD0 tokens to complete the swap.
    function testProvideUsd0ReceiveUSDCInsufficientUSD0Balance() public {
        uint256 amountPerOrder = MINIMUM_USDC_PROVIDED + 1;
        uint256 numOrders = 5;

        uint256[] memory orderIdsToTake = new uint256[](numOrders);

        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 amountToTake = amountPerOrder * numOrders;
        uint256 expectedUsd0Amount = _getUsd0WadEquivalent(amountToTake, usdcWadPrice);

        _dealStbcAndApprove(expectedUsd0Amount - 1, bob);
        vm.startPrank(bob);

        vm.expectRevert(abi.encodeWithSelector(InsufficientUSD0Balance.selector));
        swapperEngine.provideUsd0ReceiveUSDC(bob, amountToTake, orderIdsToTake, false);
        vm.stopPrank();
    }

    /// @dev Test case for providing USD0 to receive USDC when the provider has an insufficient USD0 allowance.
    ///
    /// This test creates a specified number of USDC orders with a fixed amount per order. It then attempts to provide USD0 and receive
    /// USDC, but the provider's USD0 allowance is set to be 1 token less than the expected amount.
    ///
    /// The test expects the transaction to revert since the provider has not approved
    /// enough USD0 tokens to the swapper engine contract to complete the swap.
    function testProvideUsd0ReceiveUSDCInsufficientUSD0Allowance() public {
        uint256 amountPerOrder = MINIMUM_USDC_PROVIDED + 1;
        uint256 numOrders = 5;
        uint256 amountToTake = amountPerOrder * numOrders;

        (uint256[] memory orderIdsToTake, uint256 usdcWadPrice, uint256 expectedUsd0Amount) =
            _createMultipleDepositOrders(amountPerOrder, numOrders, amountToTake);

        _dealStbcAndApprove(expectedUsd0Amount, bob);
        vm.startPrank(bob);
        IERC20(address(stbcToken)).approve(address(swapperEngine), expectedUsd0Amount - 1); // Insufficient USD0 allowance

        uint256 expectedUsd0PerOrder = _getUsd0WadEquivalent(amountPerOrder, usdcWadPrice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                swapperEngine,
                expectedUsd0PerOrder - 1,
                expectedUsd0PerOrder
            )
        );
        swapperEngine.provideUsd0ReceiveUSDC(bob, amountToTake, orderIdsToTake, false);
        vm.stopPrank();
    }

    /// @dev This test attempts to provide USD0 and receive USDC with an amount to take of zero.
    ///
    /// The test expects the transaction to revert since providing a zero amount is not allowed.
    function testProvideUsd0ReceiveUSDCZeroAmountToTake() public {
        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 1;

        vm.startPrank(bob);
        // Amount must be greater than 0
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        swapperEngine.provideUsd0ReceiveUSDC(bob, 0, orderIdsToTake, false);
        vm.stopPrank();
    }

    /// @dev Test case for providing USD0 to receive USDC with an empty array of order IDs.
    ///
    /// This test attempts to provide USD0 and receive USDC with an empty array of order IDs, effectively not specifying any orders
    /// to match against.
    ///
    /// The test expects the transaction to revert since there are no orders specified to fulfill the requested amount.
    function testProvideUsd0ReceiveUSDCEmptyOrderIds() public {
        uint256[] memory emptyOrderIds = new uint256[](0);

        uint256 amountToTake = 1000;
        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 expectedUsd0Amount = _getUsd0WadEquivalent(amountToTake, usdcWadPrice);

        _dealStbcAndApprove(expectedUsd0Amount, bob);
        vm.startPrank(bob);

        vm.expectRevert(abi.encodeWithSelector(NoOrdersIdsProvided.selector));
        swapperEngine.provideUsd0ReceiveUSDC(bob, amountToTake, emptyOrderIds, true);
        vm.stopPrank();
    }

    /// @dev Test case for providing USD0 to receive USDC with a mix of valid and invalid order IDs, where the requested amount
    /// exceeds the sum of the valid orders.
    ///
    /// The test attempts to provide USD0 and receive USDC with the prepared order IDs and partial matching disabled. It expects the
    /// transaction to revert since the requested amount cannot be fully matched by the valid orders.
    function testProvideUsd0ReceiveUSDCValidAndInvalidOrderIdsExceedingSum() public {
        uint256 amountPerOrder = MINIMUM_USDC_PROVIDED + 1;
        uint256 numOrders = 5;
        uint256 amountToTake = (amountPerOrder * 3) + 1; // Request more than the sum of valid orders

        (,, uint256 expectedUsd0Amount) =
            _createMultipleDepositOrders(amountPerOrder, numOrders, amountToTake);

        uint256[] memory orderIdsToTake = new uint256[](numOrders + 2);
        orderIdsToTake[0] = 1; // Valid order ID
        orderIdsToTake[1] = 999; // Invalid order ID
        orderIdsToTake[2] = 3; // Valid order ID
        orderIdsToTake[3] = 1000; // Invalid order ID
        orderIdsToTake[4] = 5; // Valid order ID

        _dealStbcAndApprove(expectedUsd0Amount, bob);
        vm.startPrank(bob);

        vm.expectRevert(abi.encodeWithSelector(AmountTooLow.selector));
        swapperEngine.provideUsd0ReceiveUSDC(bob, amountToTake, orderIdsToTake, false);
        vm.stopPrank();
    }

    /// @dev Test case for providing USD0 to receive USDC with partial matching disabled, where there is not enough total USDC in
    /// the orders for a complete fill.
    ///
    /// The test attempts to provide USD0 and receive USDC with partial matching disabled. It expects the transaction to revert
    /// since partial matching is not allowed and there is not enough USDC for a complete fill.
    function testProvideUsd0ReceiveUSDCPartialMatchingDisabledInsufficientUSDCFuzz(
        uint256 rawAmountPerOrder,
        uint256 rawNumOrders,
        uint256 rawExtraAmountToTake
    ) public {
        uint256 amountPerOrder =
            bound(rawAmountPerOrder, MINIMUM_USDC_PROVIDED + 1, type(uint128).max);
        uint256 numOrders = bound(rawNumOrders, 1, 10);
        uint256 extraAmountToTake = bound(rawExtraAmountToTake, 1, amountPerOrder);
        uint256 amountToTake = amountPerOrder * numOrders + extraAmountToTake;

        (uint256[] memory orderIdsToTake,, uint256 expectedUsd0Amount) =
            _createMultipleDepositOrders(amountPerOrder, numOrders, amountToTake);

        _dealStbcAndApprove(expectedUsd0Amount, bob);
        vm.startPrank(bob);

        vm.expectRevert(abi.encodeWithSelector(AmountTooLow.selector));
        swapperEngine.provideUsd0ReceiveUSDC(bob, amountToTake, orderIdsToTake, false);
        vm.stopPrank();
    }

    /// @dev Test case for providing USD0 to receive USDC with partial matching of a single order.
    ///
    /// This test creates a specified number of USDC orders with a fixed amount per order. It then attempts to provide USD0 and
    /// receive USDC by partially matching the first order, taking half of its amount.
    ///
    /// The test verifies that there is no unmatched amount, the correct amounts of USDC and USD0 are transferred, and the order
    /// states are updated accordingly. It checks that the first order is partially matched and active, while the remaining orders
    /// are untouched.
    function testProvideUsd0ReceiveUSDCPartialMatchingOneOrder() public {
        uint256 amountPerOrder = MINIMUM_USDC_PROVIDED + 1;
        uint256 numOrders = 5;
        uint256 partialAmountToTake = amountPerOrder / 2; // Take half of the first order

        // Create the specified number of USDC orders
        (,, uint256 expectedUsd0Amount) =
            _createMultipleDepositOrders(amountPerOrder, numOrders, partialAmountToTake);

        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 1;

        _dealStbcAndApprove(expectedUsd0Amount, bob);
        vm.startPrank(bob);

        uint256 unmatched =
            swapperEngine.provideUsd0ReceiveUSDC(bob, partialAmountToTake, orderIdsToTake, true);
        vm.stopPrank();

        assertEq(unmatched, 0);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), partialAmountToTake);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), expectedUsd0Amount);

        // Check order states
        (bool active1, uint256 tokenAmount1) = swapperEngine.getOrder(1);
        assertEq(active1, true);
        assertEq(tokenAmount1, amountPerOrder - partialAmountToTake);

        for (uint256 i = 1; i < numOrders; i++) {
            (bool active, uint256 tokenAmount) = swapperEngine.getOrder(i + 1);
            assertEq(active, true);
            assertEq(tokenAmount, amountPerOrder);
        }
    }

    /// @dev Test case for providing USD0 to receive USDC with partial matching, where the amount to take partially matches multiple
    /// orders.
    ///
    /// The test verifies that there is no unmatched amount, the correct amounts of USDC and USD0 are transferred, and the order
    /// states are updated accordingly. It checks that the first 3 orders are fully matched and inactive, the 4th order is partially
    /// matched and active, and the 5th order remains untouched.
    function testProvideUsd0ReceiveUSDCPartialMatchingMultipleOrders() public {
        uint256 amountPerOrder = MINIMUM_USDC_PROVIDED + 1;
        uint256 numOrders = 5;
        uint256 partialAmountToTake = (amountPerOrder * 3) + (MINIMUM_USDC_PROVIDED / 2) + 1; // Take 3.5 orders

        // Create the specified number of USDC orders
        (uint256[] memory orderIdsToTake,, uint256 expectedUsd0Amount) =
            _createMultipleDepositOrders(amountPerOrder, numOrders, partialAmountToTake);

        _dealStbcAndApprove(expectedUsd0Amount, bob);
        vm.startPrank(bob);

        uint256 unmatched =
            swapperEngine.provideUsd0ReceiveUSDC(bob, partialAmountToTake, orderIdsToTake, true);
        vm.stopPrank();

        assertEq(unmatched, 0);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), partialAmountToTake);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), expectedUsd0Amount);

        // Check order states
        for (uint256 i = 0; i < 3; i++) {
            (bool active, uint256 tokenAmount) = swapperEngine.getOrder(i + 1);
            assertEq(active, false);
            assertEq(tokenAmount, 0);
        }

        (bool active4, uint256 tokenAmount4) = swapperEngine.getOrder(4);
        assertEq(active4, true);
        assertEq(tokenAmount4, ((MINIMUM_USDC_PROVIDED / 2)));

        (bool active5, uint256 tokenAmount5) = swapperEngine.getOrder(5);
        assertEq(active5, true);
        assertEq(tokenAmount5, amountPerOrder);
    }

    /// @dev Test case for providing USD0 to receive USDC with partial matching, where the amount to take is off by one from a complete
    /// match of multiple orders.
    ///
    /// The test verifies that there is no unmatched amount, the correct amounts of USDC and USD0 are transferred, and the order states
    /// are updated accordingly. It checks that the first 2 orders are fully matched and inactive, the 3rd order has 1 token remaining
    /// and is active, and the remaining orders are untouched.

    function testProvideUsd0ReceiveUSDCPartialMatchingOffByOne() public {
        uint256 amountPerOrder = MINIMUM_USDC_PROVIDED + 1;
        uint256 numOrders = 5;
        uint256 partialAmountToTake = (amountPerOrder * 3) - 1; // Take 1 less than 3 orders

        // Create the specified number of USDC orders
        (uint256[] memory orderIdsToTake,, uint256 expectedUsd0Amount) =
            _createMultipleDepositOrders(amountPerOrder, numOrders, partialAmountToTake);

        _dealStbcAndApprove(expectedUsd0Amount, bob);
        vm.startPrank(bob);

        uint256 unmatched =
            swapperEngine.provideUsd0ReceiveUSDC(bob, partialAmountToTake, orderIdsToTake, true);
        vm.stopPrank();

        assertEq(unmatched, 0);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), partialAmountToTake);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), expectedUsd0Amount);

        // Check order states
        for (uint256 i = 0; i < 2; i++) {
            (bool active, uint256 tokenAmount) = swapperEngine.getOrder(i + 1);
            assertEq(active, false);
            assertEq(tokenAmount, 0);
        }

        (bool active3, uint256 tokenAmount3) = swapperEngine.getOrder(3);
        assertEq(active3, true);
        assertEq(tokenAmount3, 1);

        for (uint256 i = 3; i < numOrders; i++) {
            (bool active, uint256 tokenAmount) = swapperEngine.getOrder(i + 1);
            assertEq(active, true);
            assertEq(tokenAmount, amountPerOrder);
        }
    }

    /// @dev Test case for providing USD0 to receive USDC with partial matching disabled, where the amount to take is less than the
    /// total available amount across all orders.
    ///
    /// This test creates a specified number of USDC orders with a fixed amount per order. It then calculates the amount of USDC to
    /// take as the total amount across all orders minus one, plus an additional small amount. This ensures that the amount to take
    /// is less than the total available amount.
    ///
    /// The test attempts to provide USD0 and receive USDC with partial matching disabled. It expects the transaction to revert since partial matching is not allowed
    /// and the requested amount cannot be fully matched.
    function testProvideUsd0ReceiveUSDCPartialMatchingDisabled() public {
        uint256 amountPerOrder = MINIMUM_USDC_PROVIDED + 1;
        uint256 numOrders = 5;
        uint256 amountToTake = amountPerOrder * (numOrders - 1) + 1; // Take less than the total available amount

        // Create the specified number of USDC orders
        (uint256[] memory orderIdsToTake,, uint256 expectedUsd0Amount) =
            _createMultipleDepositOrders(amountPerOrder, numOrders, amountToTake);

        _dealStbcAndApprove(expectedUsd0Amount, bob);
        vm.startPrank(bob);

        uint256 unmatched =
            swapperEngine.provideUsd0ReceiveUSDC(bob, amountToTake, orderIdsToTake, false);
        assertEq(unmatched, 0);
        vm.stopPrank();
    }

    /// @dev Test case for providing USD0 to receive USDC with a mix of valid and invalid order IDs.
    ///
    /// This test creates a specified number of USDC orders with a fixed amount per order. It then prepares an array of order IDs
    /// that includes both valid and invalid order IDs. The amount to take is set to match the total amount of the valid orders.
    ///
    /// The test attempts to provide USD0 and receive USDC with the prepared order IDs. It verifies that there is no unmatched amount,
    /// the correct amounts of USDC and USD0 are transferred, and the order states are updated accordingly. It checks that the orders
    /// corresponding to the valid order IDs are fully matched and inactive, while the orders corresponding to the invalid order IDs
    /// remain unchanged.
    function testProvideUsd0ReceiveUSDCValidAndInvalidOrderIds() public {
        uint256 amountPerOrder = MINIMUM_USDC_PROVIDED + 1;
        uint256 numOrders = 5;
        uint256 amountToTake = amountPerOrder * 3; // Take 3 valid orders

        // Create the specified number of USDC orders
        (,, uint256 expectedUsd0Amount) =
            _createMultipleDepositOrders(amountPerOrder, numOrders, amountToTake);

        uint256[] memory orderIdsToTake = new uint256[](numOrders + 2);
        orderIdsToTake[0] = 1; // Valid order ID
        orderIdsToTake[1] = 999; // Invalid order ID
        orderIdsToTake[2] = 3; // Valid order ID
        orderIdsToTake[3] = 1000; // Invalid order ID
        orderIdsToTake[4] = 5; // Valid order ID

        _dealStbcAndApprove(expectedUsd0Amount, bob);
        vm.startPrank(bob);

        uint256 unmatched =
            swapperEngine.provideUsd0ReceiveUSDC(bob, amountToTake, orderIdsToTake, false);
        vm.stopPrank();

        assertEq(unmatched, 0);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), amountToTake);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), expectedUsd0Amount);
        uint256 expectedAmountPerOrder = MINIMUM_USDC_PROVIDED + 1;

        // Check order states
        (bool active1, uint256 tokenAmount1) = swapperEngine.getOrder(1);
        assertEq(active1, false);
        assertEq(tokenAmount1, 0);

        (bool active2, uint256 tokenAmount2) = swapperEngine.getOrder(2);
        assertEq(active2, true);
        assertEq(tokenAmount2, expectedAmountPerOrder);

        (bool active3, uint256 tokenAmount3) = swapperEngine.getOrder(3);
        assertEq(active3, false);
        assertEq(tokenAmount3, 0);

        (bool active4, uint256 tokenAmount4) = swapperEngine.getOrder(4);
        assertEq(active4, true);
        assertEq(tokenAmount4, expectedAmountPerOrder);

        (bool active5, uint256 tokenAmount5) = swapperEngine.getOrder(5);
        assertEq(active5, false);
        assertEq(tokenAmount5, 0);
    }

    /// @dev Test case for providing USD0 to receive USDC with a mix of valid and invalid order IDs, where the requested amount
    /// exceeds the sum of the valid orders, but partial matching is enabled.
    ///
    /// The test attempts to provide USD0 and receive USDC with the prepared order IDs and partial matching enabled. It verifies that
    /// the unmatched amount is equal to the difference between the requested amount and the total amount of the valid orders. It
    /// checks that the correct amounts of USDC and USD0 are transferred based on the partially matched amount.
    function testProvideUsd0ReceiveUSDCValidAndInvalidOrderIdsExceedingSumPartialFill() public {
        uint256 amountPerOrder = MINIMUM_USDC_PROVIDED + 1;
        uint256 numOrders = 5;
        uint256 amountToTake = (amountPerOrder * 3) + 1; // Request more than the sum of valid orders

        // Create the specified number of USDC orders
        (, uint256 usdcWadPrice, uint256 expectedUsd0Amount) =
            _createMultipleDepositOrders(amountPerOrder, numOrders, amountToTake);

        uint256[] memory orderIdsToTake = new uint256[](numOrders + 2);
        orderIdsToTake[0] = 1; // Valid order ID
        orderIdsToTake[1] = 999; // Invalid order ID
        orderIdsToTake[2] = 3; // Valid order ID
        orderIdsToTake[3] = 1000; // Invalid order ID
        orderIdsToTake[4] = 5; // Valid order ID

        _dealStbcAndApprove(expectedUsd0Amount, bob);
        vm.startPrank(bob);

        uint256 unmatched =
            swapperEngine.provideUsd0ReceiveUSDC(bob, amountToTake, orderIdsToTake, true);
        vm.stopPrank();

        assertEq(unmatched, 1); // Unmatched amount should be 1
        uint256 actualUsd0Amount = _getUsd0WadEquivalent((amountPerOrder * 3), usdcWadPrice);

        assertEq(IUSDC(address(USDC)).balanceOf(bob), amountPerOrder * 3); // Bob should receive USDC for 3 valid orders
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), actualUsd0Amount); // Alice should receive expected USD0 amount
        uint256 expectedAmountPerOrder = MINIMUM_USDC_PROVIDED + 1;

        // Check order states
        (bool active1, uint256 tokenAmount1) = swapperEngine.getOrder(1);
        assertEq(active1, false);
        assertEq(tokenAmount1, 0);

        (bool active2, uint256 tokenAmount2) = swapperEngine.getOrder(2);
        assertEq(active2, true);
        assertEq(tokenAmount2, expectedAmountPerOrder);

        (bool active3, uint256 tokenAmount3) = swapperEngine.getOrder(3);
        assertEq(active3, false);
        assertEq(tokenAmount3, 0);

        (bool active4, uint256 tokenAmount4) = swapperEngine.getOrder(4);
        assertEq(active4, true);
        assertEq(tokenAmount4, expectedAmountPerOrder);

        (bool active5, uint256 tokenAmount5) = swapperEngine.getOrder(5);
        assertEq(active5, false);
        assertEq(tokenAmount5, 0);
    }

    /// @dev Test case for providing USD0 to receive USDC with partial matching, where there is not enough total USDC in the orders
    /// for a complete fill.
    ///
    /// The test attempts to provide USD0 and receive USDC with partial matching enabled. It expects a partial match, where the
    /// unmatched amount should be equal to the extra amount requested beyond the total available USDC.
    function testProvideUsd0ReceiveUSDCPartialMatchingInsufficientUSDCFuzz(
        uint256 rawAmountPerOrder,
        uint256 rawNumOrders,
        uint256 rawExtraAmountToTake
    ) public {
        uint256 amountPerOrder =
            bound(rawAmountPerOrder, MINIMUM_USDC_PROVIDED + 1, type(uint128).max);
        uint256 numOrders = bound(rawNumOrders, 1, 10);
        uint256 extraAmountToTake = bound(rawExtraAmountToTake, 1, amountPerOrder);
        uint256 amountToTake = amountPerOrder * numOrders + extraAmountToTake;

        // Create the specified number of USDC orders
        (uint256[] memory orderIdsToTake, uint256 usdcWadPrice, uint256 expectedUsd0Amount) =
            _createMultipleDepositOrders(amountPerOrder, numOrders, amountToTake);

        _dealStbcAndApprove(expectedUsd0Amount, bob);
        vm.startPrank(bob);

        uint256 unmatched =
            swapperEngine.provideUsd0ReceiveUSDC(bob, amountToTake, orderIdsToTake, true);
        vm.stopPrank();

        assertEq(unmatched, extraAmountToTake);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), amountPerOrder * numOrders);
        assertEq(
            IERC20(address(stbcToken)).balanceOf(alice),
            _getUsd0WadEquivalent(amountPerOrder * numOrders, usdcWadPrice)
        );
    }

    /// @dev Test case for providing USD0 to receive USDC with partial matching, where there is enough total USDC in the orders for a
    /// complete fill by taking part of one of the orders.
    ///
    /// The test attempts to provide USD0 and receive USDC with partial matching enabled. It expects a complete fill with a partial
    /// match on the last order. The test verifies that there is no unmatched amount, the correct amounts of USDC and USD0 are
    /// transferred, and the order states are updated accordingly.
    function testProvideUsd0ReceiveUSDCPartialMatchingCompleteWithPartialOrderFuzz(
        uint256 rawAmountPerOrder,
        uint256 rawNumOrders,
        uint256 rawPartialFillAmount
    ) public {
        uint256 amountPerOrder =
            bound(rawAmountPerOrder, MINIMUM_USDC_PROVIDED + 1, type(uint128).max);
        uint256 numOrders = bound(rawNumOrders, 2, 10);
        uint256 partialFillAmount = bound(rawPartialFillAmount, 1, amountPerOrder - 1);
        uint256 amountToTake = amountPerOrder * (numOrders - 1) + partialFillAmount;

        // Create the specified number of USDC orders
        (uint256[] memory orderIdsToTake,, uint256 expectedUsd0Amount) =
            _createMultipleDepositOrders(amountPerOrder, numOrders, amountToTake);

        _dealStbcAndApprove(expectedUsd0Amount, bob);
        vm.startPrank(bob);

        uint256 unmatched =
            swapperEngine.provideUsd0ReceiveUSDC(bob, amountToTake, orderIdsToTake, true);
        vm.stopPrank();

        assertEq(unmatched, 0);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), amountToTake);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), expectedUsd0Amount);

        // Check order states
        for (uint256 i = 0; i < numOrders - 1; i++) {
            (bool active, uint256 tokenAmount) = swapperEngine.getOrder(i + 1);
            assertEq(active, false);
            assertEq(tokenAmount, 0);
        }

        (bool lastOrderActive, uint256 lastOrderTokenAmount) = swapperEngine.getOrder(numOrders);
        assertEq(lastOrderActive, true);
        assertEq(lastOrderTokenAmount, amountPerOrder - partialFillAmount);
    }

    /// @dev Test case for providing USD0 to receive USDC with partial matching disabled, where there is enough total USDC in the orders
    /// for a complete fill but it would require taking part of one of the orders.
    ///
    /// The test attempts to provide USD0 and receive USDC with partial matching disabled. Since partial matching is not allowed, the
    /// transaction is expected to revert even though there is technically enough total USDC available across all orders.
    function testProvideUsd0ReceiveUSDCPartialMatchingDisabledCompleteWithPartialOrderFuzz(
        uint256 rawAmountPerOrder,
        uint256 rawNumOrders,
        uint256 rawPartialFillAmount
    ) public {
        uint256 amountPerOrder =
            bound(rawAmountPerOrder, MINIMUM_USDC_PROVIDED + 1, type(uint128).max);
        uint256 numOrders = bound(rawNumOrders, 2, 10);
        uint256 partialFillAmount = bound(rawPartialFillAmount, 1, amountPerOrder - 1);
        uint256 amountToTake = amountPerOrder * (numOrders - 1) + partialFillAmount;

        // Create the specified number of USDC orders
        (uint256[] memory orderIdsToTake,, uint256 expectedUsd0Amount) =
            _createMultipleDepositOrders(amountPerOrder, numOrders, amountToTake);

        _dealStbcAndApprove(expectedUsd0Amount, bob);
        vm.startPrank(bob);

        uint256 unmatched =
            swapperEngine.provideUsd0ReceiveUSDC(bob, amountToTake, orderIdsToTake, false);
        assertEq(unmatched, 0);
        vm.stopPrank();
    }

    function testProvideUsd0ReceiveUSDCFailedWhenPaused() public {
        uint256 amountToDeposit = MINIMUM_USDC_PROVIDED + 1;
        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 1;

        // Get the current USDC price in WAD format
        uint256 usdcWadPrice = _getUsdcWadPrice(); // price of 1e6 usdc in 1e18

        // Calculate the equivalent USD0 amount based on the USDC amount and price
        uint256 expectedUsd0Amount = _getUsd0WadEquivalent(amountToDeposit, usdcWadPrice);

        assertEq(usdcWadPrice, 1e18);
        // 10000000010
        assertEq(expectedUsd0Amount, Math.mulDiv(amountToDeposit, 1e18, 1e6));
        // 1000000001000000000000

        _dealUSDCAndApprove(amountToDeposit, alice);

        _dealStbcAndApprove(expectedUsd0Amount, bob);
        vm.prank(pauser);
        swapperEngine.pause();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        swapperEngine.provideUsd0ReceiveUSDC(bob, amountToDeposit, orderIdsToTake, false);

        assertEq(IUSDC(address(USDC)).balanceOf(bob), 0);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), 0);
    }

    function testProvideUsd0WithPermitFailWhenPaused(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, MINIMUM_USDC_PROVIDED + 1, type(uint128).max);
        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 1;

        // Get the current USDC price in WAD format
        uint256 usdcWadPrice = _getUsdcWadPrice(); // price of 1e6 usdc in 1e18

        // Calculate the equivalent USD0 amount based on the USDC amount and price
        uint256 expectedUsd0Amount = _getUsd0WadEquivalent(amountToDeposit, usdcWadPrice);

        _dealUSDCAndApprove(amountToDeposit, alice);

        SigUtils sigUtils = new SigUtils(IERC20Permit(address(stbcToken)).DOMAIN_SEPARATOR());
        uint256 deadline = block.timestamp + 100;
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: bob,
            spender: address(swapperEngine),
            value: expectedUsd0Amount,
            nonce: IERC20Permit(address(stbcToken)).nonces(bob),
            deadline: deadline
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivKey, sigUtils.getTypedDataHash(permit));
        deal(address(stbcToken), bob, expectedUsd0Amount);

        vm.prank(pauser);
        swapperEngine.pause();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        swapperEngine.provideUsd0ReceiveUSDCWithPermit(
            bob, amountToDeposit, orderIdsToTake, false, expectedUsd0Amount, deadline, v, r, s
        );
        assertEq(IUSDC(address(USDC)).balanceOf(bob), 0);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), 0);
    }

    function testProvideUsd0WithPermitFailingERC20Permit() public {
        uint256 amount = MINIMUM_USDC_PROVIDED + 1;
        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 1;

        // Get the current USDC price in WAD format
        uint256 usdcWadPrice = _getUsdcWadPrice(); // price of 1e6 usdc in 1e18

        // Calculate the equivalent USD0 amount based on the USDC amount and price
        uint256 expectedUsd0Amount = _getUsd0WadEquivalent(amount, usdcWadPrice);

        _dealUSDCAndApproveAndDeposit(amount, alice);

        deal(address(stbcToken), bob, expectedUsd0Amount);

        // swap for USD0
        uint256 deadline = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(stbcToken),
            bob,
            bobPrivKey,
            address(swapperEngine),
            expectedUsd0Amount,
            deadline
        );

        vm.startPrank(bob);

        // deadline in the past
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(swapperEngine),
                0,
                expectedUsd0Amount
            )
        );
        swapperEngine.provideUsd0ReceiveUSDCWithPermit(
            bob, amount, orderIdsToTake, false, expectedUsd0Amount, deadline, v, r, s
        );

        deadline = block.timestamp + 100;

        // insufficient amount
        (v, r, s) = _getSelfPermitData(
            address(stbcToken),
            bob,
            bobPrivKey,
            address(swapperEngine),
            expectedUsd0Amount - 1,
            deadline
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(swapperEngine),
                0,
                expectedUsd0Amount
            )
        );
        swapperEngine.provideUsd0ReceiveUSDCWithPermit(
            bob, amount, orderIdsToTake, false, expectedUsd0Amount, deadline, v, r, s
        );

        // bad v

        (v, r, s) = _getSelfPermitData(
            address(stbcToken),
            bob,
            bobPrivKey,
            address(swapperEngine),
            expectedUsd0Amount - 1,
            deadline
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(swapperEngine),
                0,
                expectedUsd0Amount
            )
        );

        swapperEngine.provideUsd0ReceiveUSDCWithPermit(
            bob, amount, orderIdsToTake, false, expectedUsd0Amount, deadline, v + 1, r, s
        );
        // bad r

        (v, r, s) = _getSelfPermitData(
            address(stbcToken),
            bob,
            bobPrivKey,
            address(swapperEngine),
            expectedUsd0Amount,
            deadline
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(swapperEngine),
                0,
                expectedUsd0Amount
            )
        );
        swapperEngine.provideUsd0ReceiveUSDCWithPermit(
            bob,
            amount,
            orderIdsToTake,
            false,
            expectedUsd0Amount,
            deadline,
            v,
            keccak256("bad r"),
            s
        );
        // bad s
        (v, r, s) = _getSelfPermitData(
            address(stbcToken),
            bob,
            bobPrivKey,
            address(swapperEngine),
            expectedUsd0Amount,
            deadline
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(swapperEngine),
                0,
                expectedUsd0Amount
            )
        );
        swapperEngine.provideUsd0ReceiveUSDCWithPermit(
            bob,
            amount,
            orderIdsToTake,
            false,
            expectedUsd0Amount,
            deadline,
            v,
            r,
            keccak256("bad s")
        );

        //bad nonce
        (v, r, s) = _getSelfPermitData(
            address(stbcToken),
            bob,
            bobPrivKey,
            address(swapperEngine),
            expectedUsd0Amount,
            deadline,
            IERC20Permit(address(stbcToken)).nonces(bob) + 1
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(swapperEngine),
                0,
                expectedUsd0Amount
            )
        );
        swapperEngine.provideUsd0ReceiveUSDCWithPermit(
            bob,
            amount,
            orderIdsToTake,
            false,
            expectedUsd0Amount,
            deadline,
            v,
            r,
            keccak256("bad s")
        );
        //bad spender
        (v, r, s) = _getSelfPermitData(
            address(stbcToken),
            alice,
            alicePrivKey,
            address(swapperEngine),
            expectedUsd0Amount,
            deadline
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(swapperEngine),
                0,
                expectedUsd0Amount
            )
        );
        swapperEngine.provideUsd0ReceiveUSDCWithPermit(
            bob, amount, orderIdsToTake, false, expectedUsd0Amount, deadline, v, r, s
        );
        // this should work
        (v, r, s) = _getSelfPermitData(
            address(stbcToken),
            bob,
            bobPrivKey,
            address(swapperEngine),
            expectedUsd0Amount,
            deadline
        );
        uint256 unmatched = swapperEngine.provideUsd0ReceiveUSDCWithPermit(
            bob, amount, orderIdsToTake, false, expectedUsd0Amount, deadline, v, r, s
        );

        vm.stopPrank();
        assertEq(unmatched, 0);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), amount);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), expectedUsd0Amount);
    }

    function testProvideUsd0ReceiveUSDCWithPermit_revertIfInsufficientUSD0Balance() public {
        uint256 amountToDeposit = MINIMUM_USDC_PROVIDED + 1;
        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 1;

        // Get the current USDC price in WAD format
        uint256 usdcWadPrice = _getUsdcWadPrice(); // price of 1e6 usdc in 1e18

        // Calculate the equivalent USD0 amount based on the USDC amount and price
        uint256 expectedUsd0Amount = _getUsd0WadEquivalent(amountToDeposit, usdcWadPrice);

        _dealUSDCAndApprove(amountToDeposit, alice);

        SigUtils sigUtils = new SigUtils(IERC20Permit(address(stbcToken)).DOMAIN_SEPARATOR());
        uint256 deadline = block.timestamp + 100;
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: bob,
            spender: address(swapperEngine),
            value: expectedUsd0Amount,
            nonce: IERC20Permit(address(stbcToken)).nonces(bob),
            deadline: deadline
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivKey, sigUtils.getTypedDataHash(permit));

        vm.startPrank(bob);
        deal(address(stbcToken), bob, expectedUsd0Amount - 1);

        vm.expectRevert(abi.encodeWithSelector(InsufficientUSD0Balance.selector));
        swapperEngine.provideUsd0ReceiveUSDCWithPermit(
            bob, amountToDeposit, orderIdsToTake, false, expectedUsd0Amount, deadline, v, r, s
        );
        vm.stopPrank();
    }

    function testProvideUsd0ReceiveUSDC_revertIfInsufficientUSD0Balance() public {
        uint256 amountToDeposit = MINIMUM_USDC_PROVIDED + 1;
        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 1;

        // Get the current USDC price in WAD format
        uint256 usdcWadPrice = _getUsdcWadPrice(); // price of 1e6 usdc in 1e18

        // Calculate the equivalent USD0 amount based on the USDC amount and price
        uint256 expectedUsd0Amount = _getUsd0WadEquivalent(amountToDeposit, usdcWadPrice);

        _dealUSDCAndApprove(amountToDeposit, alice);

        vm.startPrank(bob);
        deal(address(stbcToken), bob, expectedUsd0Amount - 1);

        vm.expectRevert(abi.encodeWithSelector(InsufficientUSD0Balance.selector));
        swapperEngine.provideUsd0ReceiveUSDC(bob, amountToDeposit, orderIdsToTake, false);
        vm.stopPrank();
    }

    /// @dev Test case for providing USD0 to receive USDC with a zero amount.
    ///
    /// This test expects the transaction to revert since providing a zero amount
    /// is not allowed.
    function testProvideUsd0ReceiveUSDCWithZeroAmount() public {
        uint256[] memory orderIdsToTake = new uint256[](0);

        vm.startPrank(bob);
        // Amount must be greater than 0
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        swapperEngine.provideUsd0ReceiveUSDC(bob, 0, orderIdsToTake, false);
        vm.stopPrank();
    }

    /// @dev Test case for providing USD0 to receive USDC with an invalid order ID.
    ///
    /// This test expects the transaction to revert since the
    /// specified order ID does not exist and the requested amount cannot be fulfilled.
    function testProvideUsd0ReceiveUSDCWithInvalidOrderId() public {
        uint256 amountToTake = MINIMUM_USDC_PROVIDED + 1;
        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 999;

        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 expectedUsd0Amount = _getUsd0WadEquivalent(amountToTake, usdcWadPrice);

        _dealStbcAndApprove(expectedUsd0Amount, bob);
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(AmountTooLow.selector));
        swapperEngine.provideUsd0ReceiveUSDC(bob, amountToTake, orderIdsToTake, false);
        vm.stopPrank();
    }

    // 6.2 Testing basic flows //
    /// @dev Test case for providing USD0 to receive USDC with a large variable number of orders.
    ///
    /// This test creates a large variable number of USDC orders with a fixed amount per order. It then attempts to provide USD0 and
    /// receive USDC for all the orders.
    ///
    /// The test verifies that there is no unmatched amount, the correct amounts of USDC and USD0 are transferred between the
    /// participants, and the balances of the participants are updated accordingly.
    function testProvideUsd0ReceiveUSDCMultipleOrders(uint256 numOrders) public {
        numOrders = bound(numOrders, 10, 100);
        uint256 amountPerOrder = MINIMUM_USDC_PROVIDED + 1;

        // Create the specified number of USDC orders
        (uint256[] memory orderIdsToTake,,) =
            _createMultipleDepositOrders(amountPerOrder, numOrders, 0);

        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 expectedUsd0Amount = _getUsd0WadEquivalent(amountPerOrder * numOrders, usdcWadPrice);

        _dealStbcAndApprove(expectedUsd0Amount, bob);
        vm.startPrank(bob);

        uint256 unmatched = swapperEngine.provideUsd0ReceiveUSDC(
            bob, amountPerOrder * numOrders, orderIdsToTake, false
        );
        vm.stopPrank();

        assertEq(unmatched, 0);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), amountPerOrder * numOrders);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), expectedUsd0Amount);
    }

    /// @dev Fuzz test for provideUsd0ReceiveUSDC function.
    /// @param amountToDeposit The amount of USDC to deposit for the order.
    /// This test creates an order by depositing a reasonable amount of USDC, and then attempts to match the order
    /// by providing USD0 tokens. If the provided USD0 amount is greater than or equal to the expected USD0 amount,
    /// it expects the order to be fully matched. Otherwise, it expects a revert due to insufficient USD0 balance
    /// or allowance.
    function testProvideUsd0WithPermit(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, MINIMUM_USDC_PROVIDED + 1, type(uint128).max);
        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 1;

        // Get the current USDC price in WAD format
        uint256 usdcWadPrice = _getUsdcWadPrice(); // price of 1e6 usdc in 1e18

        // Calculate the equivalent USD0 amount based on the USDC amount and price
        uint256 expectedUsd0Amount = _getUsd0WadEquivalent(amountToDeposit, usdcWadPrice);

        _dealUSDCAndApproveAndDeposit(amountToDeposit, alice);

        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(stbcToken),
            bob,
            bobPrivKey,
            address(swapperEngine),
            expectedUsd0Amount,
            deadline
        );

        vm.startPrank(bob);
        deal(address(stbcToken), bob, expectedUsd0Amount);

        vm.expectEmit(true, true, true, true);
        emit OrderMatched(alice, bob, 1, amountToDeposit);
        uint256 unmatched = swapperEngine.provideUsd0ReceiveUSDCWithPermit(
            bob, amountToDeposit, orderIdsToTake, false, expectedUsd0Amount, deadline, v, r, s
        );
        vm.stopPrank();
        assertEq(unmatched, 0);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), amountToDeposit);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), expectedUsd0Amount);
    }

    function testProvideUsd0WithPermitShouldWorkIfPermitAlreadyUsed(uint256 amountToDeposit)
        public
    {
        amountToDeposit = bound(amountToDeposit, MINIMUM_USDC_PROVIDED + 1, type(uint128).max);
        // uint256 amountToDeposit = MINIMUM_USDC_PROVIDED + 1;
        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 1;

        // Get the current USDC price in WAD format
        uint256 usdcWadPrice = _getUsdcWadPrice(); // price of 1e6 usdc in 1e18

        // Calculate the equivalent USD0 amount based on the USDC amount and price
        uint256 expectedUsd0Amount = _getUsd0WadEquivalent(amountToDeposit, usdcWadPrice);
        deal(address(stbcToken), bob, expectedUsd0Amount);

        _dealUSDCAndApproveAndDeposit(amountToDeposit, alice);

        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitData(
            address(stbcToken),
            bob,
            bobPrivKey,
            address(swapperEngine),
            expectedUsd0Amount,
            deadline
        );

        // call permit first
        IERC20Permit(address(stbcToken)).permit(
            bob, address(swapperEngine), expectedUsd0Amount, deadline, v, r, s
        );
        vm.startPrank(bob);
        deal(address(stbcToken), bob, expectedUsd0Amount);

        vm.expectEmit(true, true, true, true);
        emit OrderMatched(alice, bob, 1, amountToDeposit);
        uint256 unmatched = swapperEngine.provideUsd0ReceiveUSDCWithPermit(
            bob, amountToDeposit, orderIdsToTake, false, expectedUsd0Amount, deadline, v, r, s
        );
        vm.stopPrank();
        assertEq(unmatched, 0);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), amountToDeposit);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), expectedUsd0Amount);
    }

    function testProvideUsd0ReceiveUSDCFuzz(uint256 usdcAmount, uint256 usd0Amount) public {
        // Setup: Create an order by depositing a reasonable amount of USDC
        usdcAmount = bound(usdcAmount, MINIMUM_USDC_PROVIDED + 1, type(uint128).max);
        _dealUSDCAndApproveAndDeposit(usdcAmount, alice);

        // Provide USD0 tokens and attempt to match the order
        usd0Amount = bound(usd0Amount, 1, type(uint128).max);
        _dealStbcAndApprove(usd0Amount, bob);
        vm.startPrank(bob);

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = 1;

        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 expectedUsd0Amount = _getUsd0WadEquivalent(usdcAmount, usdcWadPrice);

        if (usd0Amount >= expectedUsd0Amount) {
            vm.expectEmit(true, true, true, true);
            emit OrderMatched(alice, bob, 1, usdcAmount);
            uint256 unmatched =
                swapperEngine.provideUsd0ReceiveUSDC(bob, usdcAmount, orderIds, true);
            assertEq(unmatched, 0);
            assertEq(IUSDC(address(USDC)).balanceOf(bob), usdcAmount);
        } else {
            // Expect a revert due to insufficient USD0 balance
            vm.expectRevert(abi.encodeWithSelector(InsufficientUSD0Balance.selector));
            swapperEngine.provideUsd0ReceiveUSDC(bob, usdcAmount, orderIds, true);
        }

        vm.stopPrank();
    }

    /// @dev Fuzz test for provideUsd0ReceiveUSDC function with insufficient USD0 scenario.
    /// @param rawUsdcAmount The raw amount of USDC to deposit for the order.
    /// @param rawUsd0Amount The raw amount of USD0 to provide for matching the order.
    /// This test creates an order by depositing USDC, and then attempts to match the order by providing USD0 tokens.
    /// If the provided USD0 amount is greater than or equal to the expected USD0 amount, it expects a full match
    /// with no unmatched USDC. Otherwise, it expects a revert due to insufficient USD0 balance.
    function testProvideUsd0ReceiveUSDCInsufficientUsd0ScenarioFuzz(
        uint256 rawUsdcAmount,
        uint256 rawUsd0Amount
    ) public {
        // Bound the amounts to reasonable values
        uint256 usdcAmount = bound(rawUsdcAmount, MINIMUM_USDC_PROVIDED + 1, type(uint128).max);
        uint256 usd0Amount = bound(rawUsd0Amount, 0, type(uint128).max); // Allow zero to test insufficient balance handling

        _dealUSDCAndApproveAndDeposit(usdcAmount, alice);

        _dealStbcAndApprove(usd0Amount, bob);
        vm.startPrank(bob);

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = 1;

        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 expectedUsd0Amount = _getUsd0WadEquivalent(usdcAmount, usdcWadPrice);

        if (usd0Amount >= expectedUsd0Amount) {
            // Expect a full match with no unmatched USDC
            uint256 unmatched =
                swapperEngine.provideUsd0ReceiveUSDC(bob, usdcAmount, orderIds, true);
            assertEq(unmatched, 0);
            assertEq(IUSDC(address(USDC)).balanceOf(bob), usdcAmount);
            assertEq(IUSDC(address(USDC)).balanceOf(address(swapperEngine)), 0);
        } else {
            // Insufficient USD0: Expect a revert due to not sufficient USD0 to match the USDC amount
            // Expect a revert due to insufficient USD0 balance
            vm.expectRevert(abi.encodeWithSelector(InsufficientUSD0Balance.selector));
            swapperEngine.provideUsd0ReceiveUSDC(bob, usdcAmount, orderIds, true);
        }

        vm.stopPrank();
    }

    /// @dev Fuzz test for provideUsd0ReceiveUSDC function with no partial matching allowed scenario.
    /// @param rawUsdcAmount The raw amount of USDC to deposit for the order.
    /// @param rawUsd0Amount The raw amount of USD0 to provide for matching the order.
    /// This test creates an order by depositing USDC, and then attempts to match the order by providing USD0 tokens
    /// without allowing partial matching. It expects a revert since the requester has not enabled partial matches.
    function testProvideUsd0ReceiveUSDCNoPartialMatchAllowedScenarioFuzz(
        uint256 rawUsdcAmount,
        uint256 rawUsd0Amount
    ) public {
        uint256 usdcAmount =
            bound(rawUsdcAmount, MINIMUM_USDC_PROVIDED + 1, MINIMUM_USDC_PROVIDED * 2);
        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 expectedUsd0Amount = _getUsd0WadEquivalent(usdcAmount, usdcWadPrice);

        uint256 usd0Amount = bound(rawUsd0Amount, expectedUsd0Amount * 2, type(uint128).max);

        _dealUSDCAndApproveAndDeposit(usdcAmount, alice);

        _dealStbcAndApprove(usd0Amount, bob);
        vm.startPrank(bob);

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = 1;

        // Insufficient USD0: Expect a revert since Bob has not enabled partial matches:
        vm.expectRevert(abi.encodeWithSelector(AmountTooLow.selector));
        swapperEngine.provideUsd0ReceiveUSDC(bob, usdcAmount + 1, orderIds, false);
        vm.stopPrank();
    }

    /// @dev Fuzz test for provideUsd0ReceiveUSDC function with partial matching scenario.
    /// @param rawUsdcAmount The raw amount of USDC to deposit for the order.
    /// @param rawUsd0Amount The raw amount of USD0 to provide for matching the order.
    /// This test creates an order by depositing USDC, and then attempts to match the order by providing USD0 tokens
    /// with partial matching allowed. It checks that the unmatched amount is correct and that the token balances
    /// of the participants are updated correctly.
    function testProvideUsd0ReceiveUSDCPartialMatchedScenarioFuzz(
        uint256 rawUsdcAmount,
        uint256 rawUsd0Amount
    ) public {
        uint256 usdcAmount =
            bound(rawUsdcAmount, MINIMUM_USDC_PROVIDED + 1, MINIMUM_USDC_PROVIDED * 2);
        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 expectedUsd0Amount = _getUsd0WadEquivalent(usdcAmount, usdcWadPrice);
        uint256 usd0Amount = bound(rawUsd0Amount, expectedUsd0Amount * 2, type(uint128).max);
        _dealUSDCAndApproveAndDeposit(usdcAmount, alice);

        _dealStbcAndApprove(usd0Amount, bob);
        vm.startPrank(bob);

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = 1;

        uint256 unmatched =
            swapperEngine.provideUsd0ReceiveUSDC(bob, usdcAmount + 1, orderIds, true);

        assertEq(unmatched, 1);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), usdcAmount);
        assertEq(
            IERC20(address(stbcToken)).balanceOf(bob),
            usd0Amount - expectedUsd0Amount,
            "Only the usd0 amount for the partially matched usdc should be taken"
        );
        assertEq(
            IERC20(address(stbcToken)).balanceOf(alice),
            expectedUsd0Amount,
            "Only the usd0 amount for the partially matched usdc should be given"
        );
        vm.stopPrank();
    }

    /// @dev Fuzz test for provideUsd0ReceiveUSDC function with varying order IDs.
    /// @param rawUsdcAmount The raw amount of USDC to deposit for each order.
    /// @param rawUsd0Amount The raw amount of USD0 to provide for matching the orders.
    /// @param numOrdersFuzzed The fuzzed number of orders to create.
    /// This test prepares and deposits multiple USDC orders by Alice, and then attempts to match the orders
    /// by providing USD0 tokens with an array of order IDs, including potentially invalid IDs based on fuzzing input.
    /// If Bob has enough USD0 to match all valid orders fully, it expects no unmatched amount and the correct token
    /// balances. Otherwise, it expects a revert due to insufficient USD0 balance.
    function testProvideUsd0ReceiveUSDCOrderIdsFuzz(
        uint256 rawUsdcAmount,
        uint256 rawUsd0Amount,
        uint8 numOrdersFuzzed
    ) public {
        uint256 usdcAmount = bound(rawUsdcAmount, MINIMUM_USDC_PROVIDED + 1, type(uint128).max);
        uint256 usd0Amount = bound(rawUsd0Amount, 1, type(uint128).max);
        uint256 ordersUpperBound = 1000;
        uint256 numOrders = bound(numOrdersFuzzed, 1, ordersUpperBound);

        // Prepare and deposit multiple USDC orders by Alice
        _createMultipleDepositOrders(usdcAmount, numOrders, 0);

        _dealStbcAndApprove(usd0Amount, bob);
        vm.startPrank(bob);

        // Create an array of order IDs, including potentially invalid IDs based on fuzzing input
        uint256[] memory orderIds = new uint256[](numOrders);
        uint256 validOrderCount = 0;
        for (uint256 i = 0; i < numOrders; i++) {
            // Introducing fuzzing into order IDs by either choosing a valid ID or a fuzzed ID
            if (i % 2 == 0) {
                // Alternate between valid and potentially invalid
                orderIds[i] = i + 1; // Valid order IDs
                validOrderCount++;
            } else {
                orderIds[i] = i + 1 + ordersUpperBound; // Fuzzed order ID, which could be invalid
            }
        }

        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 expectedUsd0Amount = _getUsd0WadEquivalent(usdcAmount, usdcWadPrice);

        if (usd0Amount >= expectedUsd0Amount * validOrderCount) {
            // If Bob has enough USD0 to  match all orders fully

            uint256 unmatched = swapperEngine.provideUsd0ReceiveUSDC(
                bob, usdcAmount * validOrderCount, orderIds, true
            );
            assertEq(unmatched, 0); // Expecting no unmatched amount if all order IDs are valid and enough USD0 is provided
            assertEq(IUSDC(address(USDC)).balanceOf(bob), usdcAmount * validOrderCount);
        } else {
            // Expect a revert due to insufficient USD0 balance
            vm.expectRevert(abi.encodeWithSelector(InsufficientUSD0Balance.selector));
            swapperEngine.provideUsd0ReceiveUSDC(bob, usdcAmount * validOrderCount, orderIds, true);
        }

        vm.stopPrank();
    }

    /// @dev Test case for providing USD0 to receive USDC with invalid order IDs.
    ///
    /// This test expects the transaction to succeed and the valid orders to be matched, while the invalid order IDs are ignored.
    /// It verifies that there is no unmatched amount and that the balances of the participants are updated correctly with the
    /// expected amounts of USDC and USD0.
    function testProvideUsd0ReceiveUSDCInvalidOrderIds() public {
        uint256 amountPerOrder = MINIMUM_USDC_PROVIDED + 1;
        uint256 numOrders = 5;
        uint256 amountToTake = amountPerOrder * numOrders;

        (,, uint256 expectedUsd0Amount) =
            _createMultipleDepositOrders(amountPerOrder, numOrders, amountToTake);

        uint256[] memory orderIdsToTake = new uint256[](numOrders + 2);
        for (uint256 i = 0; i < numOrders; i++) {
            orderIdsToTake[i] = i + 1;
        }
        orderIdsToTake[numOrders] = 999; // Invalid order ID
        orderIdsToTake[numOrders + 1] = 1000; // Invalid order ID

        _dealStbcAndApprove(expectedUsd0Amount, bob);

        vm.startPrank(bob);
        uint256 unmatched =
            swapperEngine.provideUsd0ReceiveUSDC(bob, amountToTake, orderIdsToTake, false);
        vm.stopPrank();

        assertEq(unmatched, 0);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), amountToTake);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), expectedUsd0Amount);
    }

    /*//////////////////////////////////////////////////////////////
                            7. SWAP_USD0
    //////////////////////////////////////////////////////////////*/

    // 7.1 Testing revert properties //

    function testSwapUsd0FailWhenPaused() public {
        uint256 amountUsd0ToProvideInWad = 1000 * 1e18; // 1000 USD0
        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 1;

        vm.prank(pauser);
        swapperEngine.pause();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        swapperEngine.swapUsd0(bob, amountUsd0ToProvideInWad, orderIdsToTake, false);

        // Assert: Check the unmatched amount and token balances
        assertEq(IUSDC(address(USDC)).balanceOf(bob), 0);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), 0);
    }

    function testSwapUd0RevertIfOrderRequesterBlacklistedButPassesIfOnlyNotAllowlisted() public {
        uint256 amountUsd0ToProvideInWad = 1000 * 1e18; // 1000 USD0
        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 1;

        uint256 amountToDeposit =
            _getUsdcAmountFromUsd0WadEquivalent(amountUsd0ToProvideInWad, _getUsdcWadPrice());
        _dealUSDCAndApproveAndDeposit(amountToDeposit, alice);

        vm.prank(blacklistOperator);
        stbcToken.blacklist(alice);

        _dealStbcAndApprove(amountUsd0ToProvideInWad, bob);
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Blacklisted.selector));
        swapperEngine.swapUsd0(bob, amountUsd0ToProvideInWad, orderIdsToTake, false);
        vm.stopPrank();

        vm.startPrank(blacklistOperator);
        stbcToken.unBlacklist(alice);
        vm.stopPrank();

        vm.startPrank(bob);
        // vm.expectRevert(abi.encodeWithSelector(NotAllowlisted.selector, address(alice)));
        swapperEngine.swapUsd0(bob, amountUsd0ToProvideInWad, orderIdsToTake, false);
        vm.stopPrank();
    }

    /// @dev Fuzz test for swapUsd0 function with no partial matching allowed and insufficient orders.
    /// @param rawAmountUsd0ToProvideInWad The raw amount of USD0 to provide in WAD format.
    /// @param rawNumOrders The raw number of orders to create.
    /// This test creates a specified number of USDC orders for Alice, and then has Bob attempt to swap USD0 for USDC
    /// using the swapUsd0 function without partial matching allowed, but with insufficient orders to fulfill the
    /// requested amount. It expects the transaction to revert with the message "Failed to take the full amount of USDC
    /// requested".
    function testSwapUsd0NoPartialMatchAllowedInsufficientOrdersFuzz(
        uint256 rawAmountUsd0ToProvideInWad,
        uint256 rawNumOrders
    ) public {
        uint256 numOrders = bound(rawNumOrders, 2, 10);

        uint256 totalUSDCAmountToDeposit = MINIMUM_USDC_PROVIDED * numOrders;
        uint256 usdcWadPrice = _getUsdcWadPrice();

        uint256 minUSD0AmountRequired =
            _getUsd0WadEquivalent(totalUSDCAmountToDeposit + 1, usdcWadPrice);
        uint256 maxUSD0AmountRequired =
            _getUsd0WadEquivalent(totalUSDCAmountToDeposit + MINIMUM_USDC_PROVIDED, usdcWadPrice);

        uint256 amountUsd0ToProvideInWad =
            bound(rawAmountUsd0ToProvideInWad, minUSD0AmountRequired, maxUSD0AmountRequired);
        uint256 dust = amountUsd0ToProvideInWad % (10 ** (18 - 6));
        uint256 amountUsd0ToProvideWithoutDust = amountUsd0ToProvideInWad - dust;

        // Setup: Create USDC orders for Alice
        (uint256[] memory orderIdsToTake,,) =
            _createMultipleDepositOrders(MINIMUM_USDC_PROVIDED, numOrders, 0);

        // Ensure insufficient orders to match the USD0 amount
        vm.assertLt(
            totalUSDCAmountToDeposit,
            _getUsdcAmountFromUsd0WadEquivalent(amountUsd0ToProvideWithoutDust, usdcWadPrice)
        );

        // Execute: Bob attempts to swap USD0 for USDC
        _dealStbcAndApprove(amountUsd0ToProvideInWad, bob);
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(AmountTooLow.selector));
        swapperEngine.swapUsd0(bob, amountUsd0ToProvideInWad, orderIdsToTake, false);
        vm.stopPrank();
    }

    /// @dev Fuzz test for swapUsd0 function with partial matching allowed and insufficient orders.
    /// @param rawAmountUsd0ToProvideInWad The raw amount of USD0 to provide in WAD format.
    /// @param rawNumOrders The raw number of orders to create.
    /// This test creates a specified number of USDC orders for Alice, and then has Bob swap USD0 for USDC using the
    /// swapUsd0 function with partial matching allowed, but with insufficient orders to fulfill the requested amount.
    /// It checks that the unmatched amount is as expected (the difference between the amount to provide and the amount
    /// swapped, plus dust), and that the token balances of Alice and Bob are updated correctly.
    function testSwapUsd0PartialMatchAllowedInsufficientOrdersFuzz(
        uint256 rawAmountUsd0ToProvideInWad,
        uint256 rawNumOrders
    ) public {
        uint256 numOrders = bound(rawNumOrders, 2, 10);

        uint256 totalUSDCAmountToDeposit = MINIMUM_USDC_PROVIDED * numOrders;
        uint256 usdcWadPrice = _getUsdcWadPrice();

        uint256 minUSD0AmountRequired =
            _getUsd0WadEquivalent(totalUSDCAmountToDeposit + 1, usdcWadPrice);
        uint256 maxUSD0AmountRequired =
            _getUsd0WadEquivalent(totalUSDCAmountToDeposit + MINIMUM_USDC_PROVIDED, usdcWadPrice);

        uint256 amountUsd0ToProvideInWad =
            bound(rawAmountUsd0ToProvideInWad, minUSD0AmountRequired, maxUSD0AmountRequired);
        uint256 dust = amountUsd0ToProvideInWad % (10 ** (18 - 6));
        uint256 amountUsd0ToProvideWithoutDust = amountUsd0ToProvideInWad - dust;

        // Setup: Create USDC orders for Alice
        (uint256[] memory orderIdsToTake,,) =
            _createMultipleDepositOrders(MINIMUM_USDC_PROVIDED, numOrders, 0);

        // Execute: Bob swaps USD0 for USDC with partial matching allowed
        _dealStbcAndApprove(amountUsd0ToProvideInWad, bob);
        vm.startPrank(bob);
        uint256 unmatched =
            swapperEngine.swapUsd0(bob, amountUsd0ToProvideInWad, orderIdsToTake, true);
        vm.stopPrank();

        // Assert: Check the unmatched amount and token balances
        uint256 usdcAmountSwapped = totalUSDCAmountToDeposit;
        uint256 usd0AmountSwapped = _getUsd0WadEquivalent(usdcAmountSwapped, usdcWadPrice);
        uint256 expectedUnmatched = amountUsd0ToProvideWithoutDust - usd0AmountSwapped;

        assertEq(unmatched, expectedUnmatched + dust);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), usdcAmountSwapped);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), usd0AmountSwapped);
    }

    /// @dev Test case for swapUsd0 function with insufficient USD0 balance.
    /// This test creates a USDC order for Alice, and then has Bob attempt to swap USD0 for USDC using the swapUsd0
    /// function, but with insufficient USD0 balance. It expects the transaction to revert.
    function testSwapUsd0InsufficientUsd0Balance() public {
        uint256 amountUsd0ToProvideInWad = 1000 * 1e18;
        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 1;

        // Setup: Create a USDC order for Alice
        _dealUSDCAndApproveAndDeposit(amountUsd0ToProvideInWad, alice);

        // Execute: Bob attempts to swap USD0 for USDC with insufficient USD0 balance
        _dealStbcAndApprove(amountUsd0ToProvideInWad - 1, bob);
        vm.startPrank(bob);
        deal(address(stbcToken), bob, amountUsd0ToProvideInWad - 1);
        IERC20(address(stbcToken)).approve(address(swapperEngine), amountUsd0ToProvideInWad);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                bob,
                amountUsd0ToProvideInWad - 1,
                amountUsd0ToProvideInWad
            )
        );
        swapperEngine.swapUsd0(bob, amountUsd0ToProvideInWad, orderIdsToTake, true);
        vm.stopPrank();
    }

    /// @dev Test case for swapUsd0 function with insufficient USD0 allowance.
    /// This test creates a USDC order for Alice, and then has Bob attempt to swap USD0 for USDC using the swapUsd0
    /// function, but with insufficient USD0 allowance. It expects the transaction to revert.
    function testSwapUsd0InsufficientUsd0Allowance() public {
        uint256 amountUsd0ToProvideInWad = 1000 * 1e18;
        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 1;

        // Setup: Create a USDC order for Alice
        _dealUSDCAndApproveAndDeposit(amountUsd0ToProvideInWad, alice);

        // Execute: Bob attempts to swap USD0 for USDC with insufficient USD0 allowance
        vm.startPrank(bob);
        deal(address(stbcToken), bob, amountUsd0ToProvideInWad);
        IERC20(address(stbcToken)).approve(address(swapperEngine), amountUsd0ToProvideInWad - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                swapperEngine,
                amountUsd0ToProvideInWad - 1,
                amountUsd0ToProvideInWad
            )
        );
        swapperEngine.swapUsd0(bob, amountUsd0ToProvideInWad, orderIdsToTake, true);
        vm.stopPrank();
    }

    /// @dev Test case for swapUsd0 function with empty order IDs.
    /// This test has Bob attempt to swap USD0 for USDC using the swapUsd0 function, but with an empty array of order
    /// IDs to take. It expects the transaction to revert
    function testSwapUsd0EmptyOrderIds() public {
        uint256 amountUsd0ToProvideInWad = 1000 * 1e18;
        uint256[] memory emptyOrderIdsToTake = new uint256[](0);

        _dealStbcAndApprove(amountUsd0ToProvideInWad, bob);
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(NoOrdersIdsProvided.selector));
        swapperEngine.swapUsd0(bob, amountUsd0ToProvideInWad, emptyOrderIdsToTake, true);
        vm.stopPrank();
    }

    // 7.2 Testing basic flows //

    function testSwapUsd0FuzzOraclePrice(
        uint256 rawAmountUsd0ToProvideInWad,
        uint256 rawNumOrders,
        uint256 rawOraclePrice
    ) public {
        uint256 oraclePrice = bound(rawOraclePrice, 1, 2e18); // Ensure oracle price is within a reasonable range
        _setOraclePrice(address(USDC), oraclePrice);

        uint256 numOrders = bound(rawNumOrders, 2, 10);
        uint256 totalUSDCAmountToDeposit = MINIMUM_USDC_PROVIDED * numOrders;
        uint256 usdcWadPrice = _getUsdcWadPrice();

        uint256 minUSD0AmountRequired =
            _getUsd0WadEquivalent(MINIMUM_USDC_PROVIDED + 1, usdcWadPrice);
        uint256 maxUSD0AmountRequired =
            _getUsd0WadEquivalent(totalUSDCAmountToDeposit, usdcWadPrice);
        uint256 amountUsd0ToProvideInWad =
            bound(rawAmountUsd0ToProvideInWad, minUSD0AmountRequired, maxUSD0AmountRequired);

        (uint256[] memory orderIdsToTake,,) =
            _createMultipleDepositOrders(MINIMUM_USDC_PROVIDED, numOrders, 0);

        // Execute: Bob swaps USD0 for USDC with partial matching allowed

        _dealStbcAndApprove(amountUsd0ToProvideInWad, bob);
        vm.startPrank(bob);
        uint256 unmatched =
            swapperEngine.swapUsd0(bob, amountUsd0ToProvideInWad, orderIdsToTake, true);
        vm.stopPrank();

        // Assert: Check the unmatched amount and token balances
        uint256 usdcAmountSwapped =
            _getUsdcAmountFromUsd0WadEquivalent(amountUsd0ToProvideInWad, usdcWadPrice);
        if (totalUSDCAmountToDeposit < usdcAmountSwapped) {
            usdcAmountSwapped = totalUSDCAmountToDeposit;
        }
        uint256 usd0AmountSwapped =
            amountUsd0ToProvideInWad - IERC20(address(stbcToken)).balanceOf(bob);
        assertEq(IUSDC(USDC).balanceOf(bob), usdcAmountSwapped);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), usd0AmountSwapped);

        uint256 expectedUnmatched = IERC20(address(stbcToken)).balanceOf(bob);
        assertEq(unmatched, expectedUnmatched);

        // If we had sent 1 wei less, the USDC amount must have been less, otherwise it should have been refunded as dust
        assertLt(
            _getUsdcAmountFromUsd0WadEquivalent(usd0AmountSwapped - 1, usdcWadPrice),
            usdcAmountSwapped
        );

        // Check that the dust cannot be traded again
        if (unmatched > 0) {
            vm.startPrank(bob);
            IERC20(address(stbcToken)).approve(address(swapperEngine), unmatched);

            vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
            swapperEngine.swapUsd0(bob, unmatched, orderIdsToTake, true);
            vm.stopPrank();
        }
    }

    /// @dev Test case for swapUsd0 function with full matching.
    /// This test sets up a USDC order for Alice, then has Bob swap USD0 for USDC using the swapUsd0 function.
    /// It checks that the unmatched amount is zero and that the token balances of Alice and Bob are updated correctly.
    function testSwapUsd0FullMatch() public {
        uint256 amountUsd0ToProvideInWad = 1000 * 1e18; // 1000 USD0
        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 1;

        // Setup: Create a USDC order for Alice
        uint256 amountToDeposit =
            _getUsdcAmountFromUsd0WadEquivalent(amountUsd0ToProvideInWad, _getUsdcWadPrice());
        vm.startPrank(alice);
        deal(address(USDC), alice, amountToDeposit);
        IUSDC(address(USDC)).approve(address(swapperEngine), amountToDeposit);
        swapperEngine.depositUSDC(amountToDeposit);
        vm.stopPrank();

        // Execute: Bob swaps USD0 for USDC
        vm.startPrank(bob);
        deal(address(stbcToken), bob, amountUsd0ToProvideInWad);
        IERC20(address(stbcToken)).approve(address(swapperEngine), amountUsd0ToProvideInWad);
        uint256 unmatched =
            swapperEngine.swapUsd0(bob, amountUsd0ToProvideInWad, orderIdsToTake, false);
        vm.stopPrank();

        // Assert: Check the unmatched amount and token balances
        assertEq(unmatched, 0);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), amountToDeposit);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), amountUsd0ToProvideInWad);
    }

    /// @dev Test case for swapUsd0 function with partial matching.
    /// This test sets up a USDC order for Alice with half the amount that Bob wants to swap.
    /// Bob then swaps USD0 for USDC using the swapUsd0 function with partial matching allowed.
    /// It checks that the unmatched amount is as expected (half the original amount plus dust),
    /// and that the token balances of Alice and Bob are updated correctly.
    function testSwapUsd0PartialMatch() public {
        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 amountUsd0ToProvideInWad =
            _getUsd0WadEquivalent(MINIMUM_USDC_PROVIDED * 2, usdcWadPrice);

        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 1;

        // Setup: Create a USDC order for Alice with half the amount
        uint256 amountToDeposit =
            _getUsdcAmountFromUsd0WadEquivalent(amountUsd0ToProvideInWad / 2, _getUsdcWadPrice());
        _dealUSDCAndApproveAndDeposit(amountToDeposit, alice);

        // Execute: Bob swaps USD0 for USDC
        _dealStbcAndApprove(amountUsd0ToProvideInWad, bob);
        vm.startPrank(bob);
        uint256 unmatched =
            swapperEngine.swapUsd0(bob, amountUsd0ToProvideInWad, orderIdsToTake, true);
        vm.stopPrank();

        // Assert: Check the unmatched amount and token balances
        uint256 dust = amountUsd0ToProvideInWad % (10 ** (18 - 6));
        uint256 expectedUnmatched = (amountUsd0ToProvideInWad - dust) / 2;
        assertEq(unmatched, expectedUnmatched + dust);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), amountToDeposit);
        assertEq(
            IERC20(address(stbcToken)).balanceOf(alice),
            amountUsd0ToProvideInWad - expectedUnmatched - dust
        );
    }

    /// @dev Fuzz test for swapUsd0 function with partial matching allowed and sufficient orders at a lowered USDC price.
    /// @param rawAmountUsd0ToProvideInWad The raw amount of USD0 to provide in WAD format.
    /// @param rawNumOrders The raw number of orders to create.
    /// This test lowers the price of USDC, creates a specified number of USDC orders for Alice, and then has Bob swap
    /// USD0 for USDC using the swapUsd0 function with partial matching allowed. It checks that the unmatched amount
    /// is equal to the dust and price dust, and that the token balances of Alice and Bob are updated correctly.
    function testSwapUsd0PartialMatchAllowedSufficientOrdersLoweredUsdcPriceFuzz(
        uint256 rawAmountUsd0ToProvideInWad,
        uint256 rawNumOrders
    ) public {
        // Lower the price of USDC
        _setOraclePrice(address(USDC), 5e5); // 0.5 USD per USDC

        uint256 numOrders = bound(rawNumOrders, 2, 10);

        uint256 totalUSDCAmountToDeposit = MINIMUM_USDC_PROVIDED * numOrders;
        uint256 usdcWadPrice = _getUsdcWadPrice();
        assertEq(usdcWadPrice, 5e17);
        uint256 minUSD0AmountRequired =
            _getUsd0WadEquivalent(MINIMUM_USDC_PROVIDED + 1, usdcWadPrice);
        uint256 maxUSD0AmountRequired =
            _getUsd0WadEquivalent(totalUSDCAmountToDeposit, usdcWadPrice);

        uint256 amountUsd0ToProvideInWad =
            bound(rawAmountUsd0ToProvideInWad, minUSD0AmountRequired, maxUSD0AmountRequired);
        uint256 dust = amountUsd0ToProvideInWad % (10 ** (18 - 6));
        uint256 minUsd0 = _getUsd0WadEquivalent(1, usdcWadPrice);
        uint256 priceDust = (amountUsd0ToProvideInWad - dust) % (minUsd0);

        uint256 amountUsd0ToProvideWithoutDust = amountUsd0ToProvideInWad - dust - priceDust;

        (uint256[] memory orderIdsToTake,,) =
            _createMultipleDepositOrders(MINIMUM_USDC_PROVIDED, numOrders, 0);

        // Ensure sufficient orders to match the USD0 amount
        vm.assertGe(
            totalUSDCAmountToDeposit,
            _getUsdcAmountFromUsd0WadEquivalent(amountUsd0ToProvideWithoutDust, usdcWadPrice)
        );

        // Execute: Bob swaps USD0 for USDC with partial matching allowed
        _dealStbcAndApprove(amountUsd0ToProvideInWad, bob);
        vm.startPrank(bob);
        uint256 unmatched =
            swapperEngine.swapUsd0(bob, amountUsd0ToProvideInWad, orderIdsToTake, true);
        vm.stopPrank();

        // Assert: Check the unmatched amount and token balances
        uint256 usdcAmountSwapped =
            _getUsdcAmountFromUsd0WadEquivalent(amountUsd0ToProvideInWad, usdcWadPrice);
        if (totalUSDCAmountToDeposit < usdcAmountSwapped) {
            usdcAmountSwapped = totalUSDCAmountToDeposit;
        }
        uint256 usd0AmountSwapped = _getUsd0WadEquivalent(usdcAmountSwapped, usdcWadPrice);
        assertEq(IUSDC(USDC).balanceOf(bob), usdcAmountSwapped);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), usd0AmountSwapped);

        uint256 expectedUnmatched = amountUsd0ToProvideInWad - usd0AmountSwapped;
        assertEq(unmatched, expectedUnmatched);

        // If we had sent 1 wei less, the USDC amount must have been less, otherwise it should have been refunded as dust
        assertLt(
            _getUsdcAmountFromUsd0WadEquivalent(usd0AmountSwapped - 1, usdcWadPrice),
            usdcAmountSwapped
        );

        // Check that the dust cannot be traded again
        if (unmatched > 0) {
            vm.startPrank(bob);
            IERC20(address(stbcToken)).approve(address(swapperEngine), unmatched);

            vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
            swapperEngine.swapUsd0(bob, unmatched, orderIdsToTake, true);
            vm.stopPrank();
        }
    }

    /// @dev Fuzz test for swapUsd0 function with no partial matching allowed and sufficient orders.
    /// @param rawAmountUsd0ToProvideInWad The raw amount of USD0 to provide in WAD format.
    /// @param rawNumOrders The raw number of orders to create.
    /// This test creates a specified number of USDC orders for Alice, and then has Bob swap USD0 for USDC using the
    /// swapUsd0 function without partial matching allowed. It checks that the unmatched amount is equal to the dust,
    /// and that the token balances of Alice and Bob are updated correctly.
    function testSwapUsd0NoPartialMatchAllowedSufficientOrdersFuzz(
        uint256 rawAmountUsd0ToProvideInWad,
        uint256 rawNumOrders
    ) public {
        uint256 numOrders = bound(rawNumOrders, 2, 10);
        uint256 totalUSDCAmountToDeposit = MINIMUM_USDC_PROVIDED * numOrders;
        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 minUSD0AmountRequired =
            _getUsd0WadEquivalent(MINIMUM_USDC_PROVIDED + 1, usdcWadPrice);
        uint256 maxUSD0AmountRequired =
            _getUsd0WadEquivalent(totalUSDCAmountToDeposit, usdcWadPrice);

        uint256 amountUsd0ToProvideInWad =
            bound(rawAmountUsd0ToProvideInWad, minUSD0AmountRequired, maxUSD0AmountRequired);
        uint256 dust = amountUsd0ToProvideInWad % (10 ** (18 - 6));
        uint256 amountUsd0ToProvideWithoutDust = amountUsd0ToProvideInWad - dust;

        // Setup: Create USDC orders for Alice
        (uint256[] memory orderIdsToTake,,) =
            _createMultipleDepositOrders(MINIMUM_USDC_PROVIDED, numOrders, 0);

        // Execute: Bob swaps USD0 for USDC with partial matching allowed
        _dealStbcAndApprove(amountUsd0ToProvideInWad, bob);
        vm.startPrank(bob);
        uint256 unmatched =
            swapperEngine.swapUsd0(bob, amountUsd0ToProvideInWad, orderIdsToTake, false);
        vm.stopPrank();

        // Assert: Check the unmatched amount and token balances
        assertEq(unmatched, dust);
        assertEq(
            IUSDC(address(USDC)).balanceOf(bob),
            _getUsdcAmountFromUsd0WadEquivalent(amountUsd0ToProvideWithoutDust, _getUsdcWadPrice())
        );
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), amountUsd0ToProvideWithoutDust);
    }

    /// @dev Fuzz test for swapUsd0 function with partial matching allowed and sufficient orders.
    /// @param rawAmountUsd0ToProvideInWad The raw amount of USD0 to provide in WAD format.
    /// @param rawNumOrders The raw number of orders to create.
    /// This test creates a specified number of USDC orders for Alice, and then has Bob swap USD0 for USDC using the
    /// swapUsd0 function with partial matching allowed. It checks that the unmatched amount is equal to the dust,
    /// and that the token balances of Alice and Bob are updated correctly.
    function testSwapUsd0PartialMatchAllowedSufficientOrdersFuzz(
        uint256 rawAmountUsd0ToProvideInWad,
        uint256 rawNumOrders
    ) public {
        uint256 numOrders = bound(rawNumOrders, 2, 150);

        uint256 totalUSDCAmountToDeposit = MINIMUM_USDC_PROVIDED * numOrders;
        uint256 usdcWadPrice = _getUsdcWadPrice();

        uint256 minUSD0AmountRequired =
            _getUsd0WadEquivalent(MINIMUM_USDC_PROVIDED + 1, usdcWadPrice);
        uint256 maxUSD0AmountRequired =
            _getUsd0WadEquivalent(totalUSDCAmountToDeposit, usdcWadPrice);

        uint256 amountUsd0ToProvideInWad =
            bound(rawAmountUsd0ToProvideInWad, minUSD0AmountRequired, maxUSD0AmountRequired);
        uint256 dust = amountUsd0ToProvideInWad % (10 ** (18 - 6));
        uint256 amountUsd0ToProvideWithoutDust = amountUsd0ToProvideInWad - dust;

        // Setup: Create USDC orders for Alice
        (uint256[] memory orderIdsToTake,,) =
            _createMultipleDepositOrders(MINIMUM_USDC_PROVIDED, numOrders, 0);

        // Execute: Bob swaps USD0 for USDC with partial matching allowed
        _dealStbcAndApprove(amountUsd0ToProvideInWad, bob);
        vm.startPrank(bob);
        uint256 unmatched =
            swapperEngine.swapUsd0(bob, amountUsd0ToProvideInWad, orderIdsToTake, true);
        vm.stopPrank();

        // Assert: Check the unmatched amount and token balances
        uint256 usdcAmountSwapped =
            _getUsdcAmountFromUsd0WadEquivalent(amountUsd0ToProvideWithoutDust, usdcWadPrice);
        uint256 usd0AmountSwapped = amountUsd0ToProvideWithoutDust;

        assertEq(unmatched, dust);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), usdcAmountSwapped);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), usd0AmountSwapped);
    }

    /*//////////////////////////////////////////////////////////////
                           8. WITHDRAW_USDC
    //////////////////////////////////////////////////////////////*/

    // 8.1 Testing revert properties //

    /// @dev Test case for withdrawing USDC from an inactive order.
    ///
    /// This test expects the second withdrawal transaction to revert with the message "Order not active or does not exist" since
    /// the order is already inactive after the first withdrawal.
    function testWithdrawUSDCFromInactiveOrder() public {
        uint256 amountToDeposit = MINIMUM_USDC_PROVIDED + 1;
        _dealUSDCAndApproveAndDeposit(amountToDeposit, alice);
        vm.startPrank(alice);
        swapperEngine.withdrawUSDC(1);
        // Order not active or does not exist
        vm.expectRevert(abi.encodeWithSelector(OrderNotActive.selector));
        swapperEngine.withdrawUSDC(1);
        vm.stopPrank();
    }

    /// @dev Test case for withdrawing USDC from a non-existent order.
    ///
    /// This test expects the transaction to revert with the message "Order not active or does not exist" since the specified order
    /// ID does not correspond to any existing order.
    function testWithdrawUSDCFromNonExistentOrder() public {
        vm.startPrank(alice);
        // Order not active or does not exist
        vm.expectRevert(abi.encodeWithSelector(OrderNotActive.selector));
        swapperEngine.withdrawUSDC(999);
        vm.stopPrank();
    }

    /// @dev Test case for withdrawing USDC from an order by a non-owner.
    ///
    /// This test expects the transaction to revert since only the
    /// account that created the order (alice) is allowed to withdraw from it.
    function testWithdrawUSDCFromNonOwnerOrder() public {
        uint256 amountToDeposit = MINIMUM_USDC_PROVIDED + 1;
        _dealUSDCAndApproveAndDeposit(amountToDeposit, alice);

        vm.startPrank(bob);
        // Only the requester can cancel their order
        vm.expectRevert(abi.encodeWithSelector(NotRequester.selector));
        swapperEngine.withdrawUSDC(1);
        vm.stopPrank();
    }

    function testWithdrawUSDCShouldFailWhenPaused() public {
        uint256 amountToDeposit = MINIMUM_USDC_PROVIDED + 1;
        _dealUSDCAndApproveAndDeposit(amountToDeposit, alice);

        vm.prank(pauser);
        swapperEngine.pause();
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(alice);
        swapperEngine.withdrawUSDC(1);
    }

    // 8.2 Testing basic flows //

    function testWithdrawUSDCAfterMinimumAmountUpdate() public {
        uint256 amountToDeposit = 1000e6 + 1;
        _dealUSDCAndApproveAndDeposit(amountToDeposit, alice);

        uint256 newMinimumAmount = 50e6;
        vm.prank(admin);
        swapperEngine.updateMinimumUSDCAmountProvided(newMinimumAmount);

        vm.prank(alice);
        swapperEngine.withdrawUSDC(1);
    }

    function testWithdrawUSDCFuzz(uint256 rawAmountToDeposit) public {
        uint256 amountToDeposit =
            bound(rawAmountToDeposit, MINIMUM_USDC_PROVIDED + 1, type(uint128).max); // Ensuring the deposit is above the minimum

        _dealUSDCAndApproveAndDeposit(amountToDeposit, alice);

        vm.startPrank(alice);
        // Withdraw the USDC
        vm.expectEmit(true, true, true, true);
        emit Withdraw(alice, 1, amountToDeposit);
        swapperEngine.withdrawUSDC(1);
        assertEq(IUSDC(address(USDC)).balanceOf(alice), amountToDeposit);

        // Further withdrawal attempt should fail since the order is now inactive
        // Order not active or does not exist
        vm.expectRevert(abi.encodeWithSelector(OrderNotActive.selector));
        swapperEngine.withdrawUSDC(1);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                  9. GET_USDC_FROM_USD0_WAD_EQUIVALENT
    //////////////////////////////////////////////////////////////*/

    /// @dev Fuzz test for getUsdcAmountFromUsd0WadEquivalent function.
    /// @param rawUsd0WadAmount The raw USD0 amount in WAD format to be used for testing.
    /// This test checks that the conversion from USD0 to USDC and back to USD0 is consistent,
    /// and that the recovered USD0 amount matches the original USD0 amount without dust.
    function testGetUsdcAmountFromUsd0WadEquivalentFuzz(uint256 rawUsd0WadAmount) public view {
        uint256 usd0WadAmount = bound(rawUsd0WadAmount, 1, type(uint128).max);

        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 dust = usd0WadAmount % (10 ** (18 - 6));
        uint256 usd0WadAmountWithoutDust = usd0WadAmount - dust;

        uint256 usdcTokenAmount =
            _getUsdcAmountFromUsd0WadEquivalent(usd0WadAmountWithoutDust, usdcWadPrice);
        uint256 recoveredUsd0WadAmount = _getUsd0WadEquivalent(usdcTokenAmount, usdcWadPrice);

        assertEq(recoveredUsd0WadAmount, usd0WadAmountWithoutDust);
    }

    /// @dev Fuzz test for getUsd0WadEquivalent function.
    /// @param rawUsdcTokenAmount The raw USDC token amount to be used for testing.
    /// This test checks that the conversion from USDC to USD0 and back to USDC is consistent,
    /// and that the recovered USDC token amount matches the original USDC token amount.
    /// It also verifies that the dust (the small amount lost due to precision) is zero.
    function testGetUsd0WadEquivalentFuzz(uint256 rawUsdcTokenAmount) public view {
        uint256 usdcTokenAmount = bound(rawUsdcTokenAmount, 1, type(uint128).max);

        uint256 usdcWadPrice = _getUsdcWadPrice();
        uint256 usd0WadAmount = _getUsd0WadEquivalent(usdcTokenAmount, usdcWadPrice);

        uint256 dust = usd0WadAmount % (10 ** (18 - 6));
        assertEq(dust, 0);
        uint256 usd0WadAmountWithoutDust = usd0WadAmount - dust;

        uint256 recoveredUsdcTokenAmount =
            _getUsdcAmountFromUsd0WadEquivalent(usd0WadAmountWithoutDust, usdcWadPrice);

        assertEq(recoveredUsdcTokenAmount, usdcTokenAmount);
    }

    /*//////////////////////////////////////////////////////////////
                             10. GET_ORDERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Test case for retrieving the details of an active order.
    ///
    /// The test verifies that the order is marked as active and the token amount matches the deposited amount.
    function testGetOrderActive() public {
        uint256 amountToDeposit = MINIMUM_USDC_PROVIDED + 1;
        _dealUSDCAndApproveAndDeposit(amountToDeposit, alice);

        (bool active, uint256 tokenAmount) = swapperEngine.getOrder(1);
        assertEq(active, true);
        assertEq(tokenAmount, amountToDeposit);
    }

    /// @dev Test case for retrieving the details of an inactive order.
    ///
    /// The test verifies that the order is marked as inactive and the token amount is zero.
    function testGetOrderInactive() public {
        uint256 amountToDeposit = MINIMUM_USDC_PROVIDED + 1;
        _dealUSDCAndApproveAndDeposit(amountToDeposit, alice);
        vm.prank(alice);
        swapperEngine.withdrawUSDC(1);

        (bool active, uint256 tokenAmount) = swapperEngine.getOrder(1);
        assertEq(active, false);
        assertEq(tokenAmount, 0);
    }

    /// @dev Test case for retrieving the details of a non-existent order.
    ///
    /// The test verifies that the order is marked as inactive and the token amount is zero for the non-existent order ID.
    function testGetOrderNonExistent() public view {
        (bool active, uint256 tokenAmount) = swapperEngine.getOrder(999);
        assertEq(active, false);
        assertEq(tokenAmount, 0);
    }

    /// @dev Test case for retrieving the next order ID.
    ///
    /// The test verifies that the next order ID is incremented by one after each order creation.
    function testGetNextOrderId() public {
        uint256 nextOrderId = swapperEngine.getNextOrderId();
        assertEq(nextOrderId, 1);

        uint256 amountToDeposit = MINIMUM_USDC_PROVIDED + 1;
        _dealUSDCAndApproveAndDeposit(amountToDeposit, alice);

        nextOrderId = swapperEngine.getNextOrderId();
        assertEq(nextOrderId, 2);
    }
}
