// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Pausable} from "openzeppelin-contracts/utils/Pausable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IUSDC} from "test/interfaces/IUSDC.sol";
import {SetupTest} from "./setup.t.sol";
import {IRwaMock} from "src/interfaces/token/IRwaMock.sol";
import {RwaMock} from "src/mock/rwaMock.sol";
import {MyERC20} from "src/mock/myERC20.sol";
import {Usd0} from "src/token/Usd0.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import {Normalize} from "src/utils/normalize.sol";

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {DaoCollateral} from "src/daoCollateral/DaoCollateral.sol";
import {IOracle} from "src/interfaces/oracles/IOracle.sol";

import {Approval, Intent} from "src/interfaces/IDaoCollateral.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SigUtils} from "test/utils/sigUtils.sol";
import {
    MAX_REDEEM_FEE,
    SCALAR_ONE,
    CONTRACT_USD0,
    CONTRACT_SWAPPER_ENGINE,
    SCALAR_TEN_KWEI,
    USD0_MINT,
    USYC,
    INTENT_TYPE_HASH,
    SWAPPER_ENGINE,
    MINIMUM_USDC_PROVIDED,
    INTENT_MATCHING_ROLE,
    NONCE_THRESHOLD_SETTER_ROLE
} from "src/constants.sol";
import {USDC, USYC_PRICE_FEED_MAINNET} from "src/mock/constants.sol";
import {SwapperEngine} from "src/swapperEngine/SwapperEngine.sol";
import {
    SameValue,
    AmountTooLow,
    AmountTooBig,
    CBRIsTooHigh,
    CBRIsNull,
    RedeemMustNotBePaused,
    RedeemMustBePaused,
    SwapMustNotBePaused,
    SwapMustBePaused,
    RedeemFeeTooBig,
    NoOrdersIdsProvided,
    InvalidSigner,
    ExpiredSignature,
    InvalidDeadline,
    ApprovalFailed,
    InvalidOrderAmount
} from "src/errors.sol";

import {console} from "forge-std/console.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/mocks/ERC1271WalletMock.sol";

contract DaoCollateralTest is SetupTest, DaoCollateral {
    using Normalize for uint256;

    ERC1271WalletMock public erc1271Mock;

    event OrderMatched(
        address indexed usdcProviderAddr,
        address indexed usd0Provider,
        uint256 indexed orderId,
        uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                            1. SETUP & HELPERS
    //////////////////////////////////////////////////////////////*/
    function setUp() public virtual override {
        uint256 forkId = vm.createFork("eth");
        vm.selectFork(forkId);
        super.setUp();

        vm.label(address(USDC), "USDC"); //uses mainnet fork to set up USDC contract
        _setOraclePrice(address(USDC), 1e6);

        erc1271Mock = new ERC1271WalletMock(alice);
        vm.deal(alice, 1 ether);
    }

    // This setup create a new RWA token with X decimals and set the price to 1
    function setupCreationRwa1(uint8 decimals) public returns (RwaMock, Usd0) {
        rwaFactory.createRwa("Hashnote US Yield Coin", "USYC", decimals);
        address token = rwaFactory.getRwaFromSymbol("USYC");
        vm.label(token, "USYC Mock");

        _whitelistRWA(token, alice);
        _whitelistRWA(token, address(daoCollateral));
        _whitelistRWA(token, treasury);
        _linkSTBCToRwa(IRwaMock(token));
        Usd0 stbc = stbcToken;
        // add mock oracle for rwa token
        whitelistPublisher(address(token), address(stbc));
        _setupBucket(token, address(stbc));
        vm.label(USYC_PRICE_FEED_MAINNET, "USYC_PRICE_FEED");
        _setOraclePrice(token, 10 ** decimals);

        return (RwaMock(token), stbc);
    }

    function setupCreationRwa2(uint8 decimals) public returns (RwaMock, Usd0) {
        rwaFactory.createRwa("Hashnote US Yield Coin 2", "USYC2", decimals);
        address token = rwaFactory.getRwaFromSymbol("USYC2");
        vm.label(token, "USYC2 Mock");

        _whitelistRWA(token, alice);
        _whitelistRWA(token, address(daoCollateral));
        _whitelistRWA(token, treasury);
        _linkSTBCToRwa(IRwaMock(token));
        Usd0 stbc = stbcToken;
        // add mock oracle for rwa token
        whitelistPublisher(address(token), address(stbc));
        _setupBucket(token, address(stbc));
        vm.label(USYC_PRICE_FEED_MAINNET, "USYC_PRICE_FEED");
        _setOraclePrice(token, 10 ** decimals);

        return (RwaMock(token), stbc);
    }

    // This setup create a new RWA token with X decimals, mint it to alice and set the price to 1
    function setupCreationRwa1_withMint(uint8 decimals, uint256 amount)
        public
        returns (RwaMock, Usd0)
    {
        (RwaMock token, Usd0 stbc) = setupCreationRwa1(decimals);
        deal(address(token), treasury, amount);
        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(daoCollateral), amount);
        return (token, stbc);
    }

    function setupCreationRwa2_withMint(uint8 decimals, uint256 amount)
        public
        returns (RwaMock, Usd0)
    {
        (RwaMock token, Usd0 stbc) = setupCreationRwa2(decimals);
        deal(address(token), treasury, amount);
        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(daoCollateral), amount);
        return (token, stbc);
    }

    function setupSwapRWAToStbc_withDeposit(uint256 amountToDeposit)
        public
        returns (RwaMock, uint256, uint256[] memory, Approval memory)
    {
        uint256 numOrders = 2;
        uint256 rwaAmount = 42_000 * 1e6;
        (RwaMock rwaMock,) = setupCreationRwa1_withMint(6, rwaAmount);
        address rwaToken = address(rwaMock);

        // Setup: Create a USDC order for Bob
        vm.startPrank(bob);
        deal(address(USDC), bob, amountToDeposit * 2);
        IUSDC(address(USDC)).approve(address(swapperEngine), amountToDeposit * 2);
        swapperEngine.depositUSDC(amountToDeposit);
        swapperEngine.depositUSDC(amountToDeposit);
        vm.stopPrank();

        /**
         * inputs
         */
        uint256[] memory orderIdsToTake = new uint256[](numOrders);
        orderIdsToTake[0] = 1;

        Approval memory approval = _getAliceApproval(rwaAmount, rwaToken);

        vm.mockCall(
            address(classicalOracle),
            abi.encodeWithSelector(IOracle.getPrice.selector, rwaToken),
            abi.encode(1e18)
        );

        return (rwaMock, rwaAmount, orderIdsToTake, approval);
    }

    function setupSwapRWAtoStbcIntent_withoutDeposit(
        address recipientIntent,
        address rwaTokenArg,
        address rwaIntent,
        uint256 deadlineIntent,
        uint256 deadlinePermit
    ) public returns (Intent memory, uint256[] memory, Approval memory) {
        /**
         * inputs
         */
        uint256[] memory orderIdsToTake = new uint256[](2);
        address rwaToken = rwaTokenArg;
        orderIdsToTake[0] = 1;

        Approval memory approval = Approval({deadline: deadlinePermit, v: 0, r: 0, s: 0});

        bytes memory signature = abi.encodePacked(uint8(0), bytes32(0), bytes32(0));

        Intent memory intent = Intent({
            recipient: recipientIntent,
            rwaToken: rwaIntent,
            amountInTokenDecimals: 42_000 * 1e6,
            deadline: deadlineIntent,
            signature: signature
        });

        SigUtils sigUtils = new SigUtils(IERC20Permit(rwaToken).DOMAIN_SEPARATOR());
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: alice,
            spender: address(daoCollateral),
            value: 42_000 * 1e6,
            nonce: IERC20Permit(rwaToken).nonces(alice),
            deadline: deadlinePermit
        });
        (approval.v, approval.r, approval.s) =
            vm.sign(alicePrivKey, sigUtils.getTypedDataHash(permit));

        uint256 intentNonce = daoCollateral.nonces(intent.recipient);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePrivKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    daoCollateral.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            INTENT_TYPE_HASH,
                            intent.recipient,
                            intent.rwaToken,
                            intent.amountInTokenDecimals,
                            intentNonce,
                            intent.deadline
                        )
                    )
                )
            )
        );

        intent.signature = abi.encodePacked(r, s, v); // note the order of r and s

        vm.mockCall(
            address(classicalOracle),
            abi.encodeWithSelector(IOracle.getPrice.selector, rwaToken),
            abi.encode(1e18)
        );

        return (intent, orderIdsToTake, approval);
    }

    function setupSwapRWAtoStbcIntent_withDeposit(
        address recipientIntent,
        address rwaMock,
        address rwaIntent,
        uint256 deadlineIntent,
        uint256 deadlinePermit
    ) public returns (Intent memory, uint256[] memory, Approval memory) {
        (Intent memory intent, uint256[] memory orderIdsToTake, Approval memory approval) =
        setupSwapRWAtoStbcIntent_withoutDeposit(
            recipientIntent, rwaMock, rwaIntent, deadlineIntent, deadlinePermit
        );
        uint256 amountToDeposit =
            _getUsdcAmountFromUsd0WadEquivalent(42_000 * 1e6 * 1e18, _getUsdcWadPrice());

        vm.startPrank(bob);
        deal(address(USDC), bob, amountToDeposit);
        IUSDC(address(USDC)).approve(address(swapperEngine), amountToDeposit);
        swapperEngine.depositUSDC(amountToDeposit);
        vm.stopPrank();

        return (intent, orderIdsToTake, approval);
    }

    /*//////////////////////////////////////////////////////////////
                        2. INTERNAL & PRIVATE
    //////////////////////////////////////////////////////////////*/
    function _getAlicePermitData(uint256 deadline, address token, address spender, uint256 amount)
        internal
        returns (uint256, uint8, bytes32, bytes32)
    {
        // to avoid compiler error
        uint256 deadlineOk = deadline;
        (uint8 v, bytes32 r, bytes32 s) =
            _getSelfPermitData(token, alice, alicePrivKey, spender, amount, deadlineOk);
        return (deadline, v, r, s);
    }

    function _getAliceApproval(uint256 amount, address rwaToken)
        internal
        returns (Approval memory)
    {
        Approval memory approval = Approval({deadline: block.timestamp + 100, v: 0, r: 0, s: 0});
        SigUtils sigUtils = new SigUtils(IERC20Permit(rwaToken).DOMAIN_SEPARATOR());
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: alice,
            spender: address(daoCollateral),
            value: amount,
            nonce: IERC20Permit(rwaToken).nonces(alice),
            deadline: approval.deadline
        });
        (approval.v, approval.r, approval.s) =
            vm.sign(alicePrivKey, sigUtils.getTypedDataHash(permit));

        return approval;
    }

    // This function returns the USDC price in WAD format
    function _getUsdcWadPrice() private view returns (uint256) {
        return classicalOracle.getPrice(USDC);
    }

    // This function returns the USDC amount from an amount of Usd0
    function _getUsdcAmountFromUsd0WadEquivalent(uint256 usd0WadAmount, uint256 usdcWadPrice)
        private
        view
        returns (uint256 usdcTokenAmountInNativeDecimals)
    {
        uint8 decimals = IERC20Metadata(USDC).decimals();
        usdcTokenAmountInNativeDecimals =
            usd0WadAmount.wadTokenAmountForPrice(usdcWadPrice, decimals);
    }

    /*//////////////////////////////////////////////////////////////
                            3. INITIALIZE
    //////////////////////////////////////////////////////////////*/
    function testNewDaoCollateralShouldFailIfWrongParameters() public {
        DaoCollateral daoCollateralTmp = new DaoCollateral();
        _resetInitializerImplementation(address(daoCollateralTmp));

        vm.expectRevert(abi.encodeWithSelector(NullContract.selector));
        daoCollateralTmp.initialize(address(0), 0);

        daoCollateralTmp = new DaoCollateral();
        _resetInitializerImplementation(address(daoCollateralTmp));

        vm.expectRevert(abi.encodeWithSelector(RedeemFeeTooBig.selector));
        daoCollateralTmp.initialize(address(registryContract), MAX_REDEEM_FEE + 1);
    }

    function testNewDaoCollateralV1ShouldFailIfAlreadyInitialized() public {
        DaoCollateral daoCollateralTmp = new DaoCollateral();
        _resetInitializerImplementation(address(daoCollateralTmp));

        vm.expectRevert(abi.encodeWithSelector(NullContract.selector));
        daoCollateralTmp.initializeV1(address(0));

        daoCollateralTmp.initializeV1(address(registryContract));
    }

    /*//////////////////////////////////////////////////////////////
                                4. SWAP
    //////////////////////////////////////////////////////////////*/
    // 4.1 Testing revert properties //
    function testRWASwapDoesNotNeedToBeAuthorized(uint256 amount) public {
        amount = bound(amount, 1e6, type(uint128).max - 1);
        (RwaMock token,) = setupCreationRwa1_withMint(6, amount);

        vm.prank(alice);
        // expect not authorized
        // vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        daoCollateral.swap(address(token), amount, 0);
    }

    function testRWASwapAmountTooBig() public {
        uint256 amount = type(uint128).max;
        amount += 1;
        (RwaMock token,) = setupCreationRwa1_withMint(6, amount);

        vm.expectRevert(abi.encodeWithSelector(AmountTooBig.selector));
        vm.prank(alice);
        daoCollateral.swap(address(token), amount, 0);
    }

    function testRWASwapWithPermitAmountTooBig() public {
        uint256 amount = type(uint128).max;
        amount += 1;
        (RwaMock token,) = setupCreationRwa1_withMint(6, amount);

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = _getAlicePermitData(
            block.timestamp + 1 days, address(token), address(daoCollateral), amount
        );

        vm.expectRevert(abi.encodeWithSelector(AmountTooBig.selector));
        vm.prank(alice);
        daoCollateral.swapWithPermit(address(token), amount, amount, deadline, v, r, s);
    }

    function testSwapShouldFailIfAmountTooLow() public {
        uint256 amount = 10_000_000_000;
        (RwaMock token,) = setupCreationRwa1_withMint(6, amount);

        // it is the same as price is 1e18 except for the imprecision
        uint256 amountInUsd = amount * 1e12;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AmountTooLow.selector));
        daoCollateral.swap(address(token), amount, amountInUsd + 1);
    }

    function testSwapShouldFailIfAmountZero() public {
        uint256 amount = 0;
        (RwaMock token,) = setupCreationRwa1_withMint(6, amount);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        daoCollateral.swap(address(token), amount, 0);
    }

    function testSwapWithPermitShouldFailIfAmountTooLow() public {
        uint256 amount = 10_000_000_000;
        (RwaMock token,) = setupCreationRwa1_withMint(6, amount);

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = _getAlicePermitData(
            block.timestamp + 1 days, address(token), address(daoCollateral), amount
        );

        // it is the same as price is 1e18 except for the imprecision
        uint256 amountInUsd = amount * 1e12;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AmountTooLow.selector));
        daoCollateral.swapWithPermit(address(token), amount, amountInUsd + 1, deadline, v, r, s);
    }

    function testSwapShouldFailIfInvalidToken() public {
        uint256 amount = 10_000_000_000;
        setupCreationRwa1_withMint(6, amount);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(InvalidToken.selector));
        daoCollateral.swap(address(0x21), amount, 0);
    }

    function testSwapWithPermitShouldFailIfInvalidToken() public {
        uint256 amount = 10_000_000_000;
        setupCreationRwa1_withMint(6, amount);

        vm.prank(alice);
        rwaFactory.createRwa("Hashnote US Yield Coin2", "USYC2", 6);
        address invalidToken = rwaFactory.getRwaFromSymbol("USYC2");

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = _getAlicePermitData(
            block.timestamp + 1 days, address(invalidToken), address(daoCollateral), amount
        );

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(InvalidToken.selector));
        daoCollateral.swapWithPermit(invalidToken, amount, amount, deadline, v, r, s);
    }

    function testSwapWithPermitFailingERC20Permit() public {
        uint256 amount = 100e6;
        (RwaMock token,) = setupCreationRwa1_withMint(6, amount);

        // swap for USD0
        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            _getAlicePermitData(block.timestamp - 1, address(token), address(daoCollateral), amount);
        vm.startPrank(alice);
        token.approve(address(daoCollateral), 0);

        // deadline in the past
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(daoCollateral), 0, amount
            )
        );
        daoCollateral.swapWithPermit(address(token), amount, amount, deadline, v, r, s);
        deadline = block.timestamp + 100;

        // insufficient amount
        (, v, r, s) =
            _getAlicePermitData(deadline, address(token), address(daoCollateral), amount - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(daoCollateral), 0, amount
            )
        );
        daoCollateral.swapWithPermit(address(token), amount, amount, deadline, v, r, s);

        // bad v
        (, v, r, s) = _getAlicePermitData(deadline, address(token), address(daoCollateral), amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(daoCollateral), 0, amount
            )
        );

        daoCollateral.swapWithPermit(address(token), amount, amount, deadline, v + 1, r, s);

        // bad r
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(daoCollateral), 0, amount
            )
        );
        daoCollateral.swapWithPermit(
            address(token), amount, amount, deadline, v, keccak256("bad r"), s
        );

        // bad s
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(daoCollateral), 0, amount
            )
        );
        daoCollateral.swapWithPermit(
            address(token), amount, amount, deadline, v, r, keccak256("bad s")
        );

        //bad nonce
        (v, r, s) = _getSelfPermitData(
            address(token),
            alice,
            alicePrivKey,
            address(daoCollateral),
            amount,
            deadline,
            IERC20Permit(address(stbcToken)).nonces(alice) + 1
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(daoCollateral), 0, amount
            )
        );
        daoCollateral.swapWithPermit(address(token), amount, amount, deadline, v, r, s);

        //bad spender
        (v, r, s) = _getSelfPermitData(
            address(token),
            bob,
            bobPrivKey,
            address(daoCollateral),
            amount,
            deadline,
            IERC20Permit(address(stbcToken)).nonces(bob)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(daoCollateral), 0, amount
            )
        );
        daoCollateral.swapWithPermit(address(token), amount, amount, deadline, v, r, s);
        vm.stopPrank();
    }

    function testSwapPausedAfterCBROn() public {
        (RwaMock rwa1, Usd0 stbc) = setupCreationRwa1_withMint(6, 200e6);
        assertEq(classicalOracle.getPrice(address(rwa1)), 1e18);

        // Alice swaps RWA for USD0
        vm.startPrank(alice);
        ERC20(address(rwa1)).approve(address(daoCollateral), 100e6);
        daoCollateral.swap(address(rwa1), 100e6, 100e6);
        vm.stopPrank();

        // Check balances after swap
        assertEq(ERC20(address(stbc)).balanceOf(alice), 100e18);
        assertEq(ERC20(address(rwa1)).balanceOf(treasury), 300e6);
        assertEq(stbc.balanceOf(usdInsurance), 0);
        assertEq(ERC20(address(stbc)).balanceOf(treasury), 0);
        assertEq(ERC20(address(stbc)).totalSupply(), 100e18);

        // Update oracle price
        _setOraclePrice(address(rwa1), 25e4);
        assertEq(classicalOracle.getPrice(address(rwa1)), 25e16);

        // Activate and check cbr coefficient
        vm.prank(admin);
        daoCollateral.setRedeemFee(0);
        vm.prank(admin);
        daoCollateral.activateCBR(0.5 ether);

        // Try to swap
        vm.prank(alice);
        ERC20(address(rwa1)).approve(address(daoCollateral), 100e6);
        vm.expectRevert(abi.encodeWithSelector(SwapMustNotBePaused.selector));
        // Should revert
        daoCollateral.swap(address(rwa1), 100e6, 100e6);
        vm.stopPrank();

        // Swap is paused
        assertEq(daoCollateral.isSwapPaused(), true);
        assertEq(daoCollateral.isCBROn(), true);
        assertEq(daoCollateral.cbrCoef(), 0.5 ether);
        vm.stopPrank();
    }

    // 4.2 Testing basic flows //
    function testRWASwap(uint256 amount) public returns (RwaMock, Usd0) {
        amount = bound(amount, 1e6, type(uint128).max - 1);
        (RwaMock token, Usd0 stbc) = setupCreationRwa1_withMint(6, amount);

        uint256 amountInUsd = amount * 1e12;
        vm.prank(alice);
        daoCollateral.swap(address(token), amount, amountInUsd);
        // it is the same as price is 1e18 except for the imprecision

        assertEq(stbc.balanceOf(alice), amountInUsd);
        return (token, stbc);
    }

    function testRWASwapWithPermit(uint256 amount) public {
        amount = bound(amount, 1e6, type(uint128).max - 1);
        (RwaMock token, Usd0 stbc) = setupCreationRwa1_withMint(6, amount);

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = _getAlicePermitData(
            block.timestamp + 1 days, address(token), address(daoCollateral), amount
        );

        vm.prank(alice);
        daoCollateral.swapWithPermit(address(token), amount, amount, deadline, v, r, s);
        // it is the same as price is 1e18 except for the imprecision
        uint256 amountInUsd = amount * 1e12;
        assertEq(stbc.balanceOf(alice), amountInUsd);
    }

    function testRWAWith27DecimalsSwap(uint256 amount) public returns (RwaMock, Usd0) {
        amount = bound(amount, 1e18, type(uint128).max - 1);
        (RwaMock token, Usd0 stbc) = setupCreationRwa1_withMint(27, amount);
        _setOraclePrice(address(token), 1000e27);
        uint256 amountInUsd = (amount * 1000e18) / 1e27;
        vm.prank(alice);
        daoCollateral.swap(address(token), amount, 0);
        // the formula to be used to calculate the correct amount of USD0 should be rwaAmount * price / rwaDecimals
        assertApproxEqRel(stbc.balanceOf(alice), amountInUsd, 0.000001e18);
        // RWA token is now on bucket and not on dao Collateral
        assertEq(token.balanceOf(address(daoCollateral)), 0);
        assertEq(token.balanceOf(treasury), amount * 2);
        assertEq(token.balanceOf(alice), 0);

        return (token, stbc);
    }

    function testRWAWith27DecimalsSwapWithPermit(uint256 amount) public {
        amount = bound(amount, 1e18, type(uint128).max - 1);
        (RwaMock token, Usd0 stbc) = setupCreationRwa1_withMint(27, amount);
        _setOraclePrice(address(token), 1000e27);

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = _getAlicePermitData(
            block.timestamp + 1 days, address(token), address(daoCollateral), amount
        );

        vm.prank(alice);
        daoCollateral.swapWithPermit(address(token), amount, 0, deadline, v, r, s);
        // the formula to be used to calculate the correct amount of USD0 should be rwaAmount * price / rwaDecimals
        uint256 amountInUsd = amount * 1000e18 / 1e27;
        assertApproxEqRel(stbc.balanceOf(alice), amountInUsd, 0.000001e18);
        // RWA token is now on bucket and not on dao Collateral
        assertEq(token.balanceOf(address(daoCollateral)), 0);
        assertEq(token.balanceOf(treasury), amount * 2);
        assertEq(token.balanceOf(alice), 0);
    }

    // swap 3 times USD => USD0  for a total of "amount" USD
    // 1st swap of 1/4 th of the amount
    // 2nd swap of half of the amount
    // 3rd swap of 1/4 th of the amount
    function testMultipleSwapsTwoTimesFromSecurity(uint256 amount) public {
        amount = bound(amount, 40e6, (type(uint128).max) - 100e6 - 1);
        // make sure it can be divided by four
        amount = amount - (amount % 4);
        uint256 wholeAmount = amount + 100e6;

        (RwaMock token, Usd0 stbc) = setupCreationRwa1_withMint(6, wholeAmount);

        uint256 tokenBalanceBefore = token.balanceOf(alice);
        assertEq(tokenBalanceBefore, wholeAmount);

        vm.startPrank(alice);
        // multiple swap from USD => USD0
        // will swap  for 1/4 of the amount
        uint256 amount1fourth = amount / 4;

        daoCollateral.swap(address(token), amount1fourth, 0);
        assertEq(stbc.balanceOf(alice), amount1fourth * 1e12);
        uint256 amountHalf = amount / 2;
        // will swap for 1/2 of the amount
        daoCollateral.swap(address(token), amountHalf, 0);
        assertEq(stbc.balanceOf(alice), (amount1fourth + amountHalf) * 1e12);
        // will swap for 1/4of the amount
        daoCollateral.swap(address(token), amount1fourth, 0);
        assertEq(stbc.balanceOf(alice), (amount1fourth + amountHalf + amount1fourth) * 1e12);
        vm.stopPrank();
    }

    // testSwapWithSeveralRWA
    function testSwapWithSeveralRWA(uint256 rawAmount) public {
        rawAmount = bound(rawAmount, 1e6, type(uint128).max - 1);
        (RwaMock rwa1, Usd0 stbc) = setupCreationRwa1_withMint(6, rawAmount);

        (RwaMock rwa2,) = setupCreationRwa2(18);

        // we need to whitelist alice for rwa
        _whitelistRWA(address(rwa2), bob);
        IRwaMock(rwa2).mint(bob, rawAmount);

        // add mock oracle for rwa token
        vm.prank(admin);
        _setOraclePrice(address(rwa2), 1e18);

        uint256 amount = ERC20(address(rwa1)).balanceOf(alice);
        // push MMF price to 1.01$
        _setOraclePrice(address(rwa1), 1.01e6);
        assertEq(classicalOracle.getPrice(address(rwa1)), 1.01e18);
        // considering amount of $ find corresponding amount of MMF
        uint256 amountInRWA = (amount * 1e18) / classicalOracle.getPrice(address(rwa1));
        uint256 oracleQuote = classicalOracle.getQuote(address(rwa1), amountInRWA);
        uint256 approxAmount = (amountInRWA * 1.01e6) / 1e6;
        assertApproxEqRel(approxAmount, amount, 0.0001 ether);
        assertEq(oracleQuote, approxAmount);
        // bob and bucket distribution need to be whitelisted
        _whitelistRWA(address(rwa1), bob);

        rwa1.mint(bob, amountInRWA);
        assertEq(ERC20(address(rwa1)).balanceOf(bob), amountInRWA);
        vm.startPrank(bob);
        ERC20(address(rwa1)).approve(address(daoCollateral), amountInRWA);
        vm.label(address(rwa1), "rwa1");
        vm.label(address(rwa2), "rwa2");
        vm.label(address(classicalOracle), "ClassicalOracle");
        // we swap amountInRWA of MMF for amount STBC
        daoCollateral.swap(address(rwa1), amountInRWA, 0);
        vm.stopPrank();
        assertApproxEqRel(ERC20(address(stbc)).balanceOf(bob), amount * 1e12, 0.000001 ether);

        // bob redeems his stbc for MMF
        vm.startPrank(bob);
        assertEq(ERC20(address(rwa1)).balanceOf(bob), 0);

        uint256 stbcBalance = ERC20(address(stbc)).balanceOf(bob);

        stbc.approve(address(daoCollateral), stbcBalance);

        daoCollateral.redeem(address(rwa1), stbcBalance, 0);

        // fee is 0.1% and goes to treasury
        assertApproxEqRel(
            ERC20(address(stbc)).balanceOf(treasury), _getDotOnePercent(amount * 1e12), 0.0012 ether
        );
        uint256 amountRedeemedMinusFee = stbcBalance - ERC20(address(stbc)).balanceOf(treasury);
        // considering amount of $ find corresponding amount of MMF
        amountInRWA = (amountRedeemedMinusFee * 1e6) / classicalOracle.getPrice(address(rwa1));
        assertApproxEqRel(ERC20(address(rwa1)).balanceOf(bob), amountInRWA, 0.000002 ether);
        // bob doesn't own STBC anymore
        assertEq(ERC20(address(stbc)).balanceOf(bob), 0);

        vm.stopPrank();
        // swap rwa2 for stbc
        amount = ERC20(address(rwa2)).balanceOf(bob);
        assertGt(amount, 0);
        // push MMF price to 1.21e18$
        uint256 oraclePrice = 1.21e18;
        _setOraclePrice(address(rwa2), oraclePrice);
        assertEq(classicalOracle.getPrice(address(rwa2)), oraclePrice);
        // considering amount of $ find corresponding amount of MMF
        uint256 amountInRWA2 = (amount * 1 ether) / classicalOracle.getPrice(address(rwa2));
        oracleQuote = classicalOracle.getQuote(address(rwa2), amountInRWA2);
        approxAmount = (amountInRWA2 * oraclePrice) / 1e18;
        assertApproxEqRel(approxAmount, amount, 0.0001 ether);
        assertEq(oracleQuote, approxAmount);
        // bucket distribution need to be whitelisted
        _whitelistRWA(address(rwa2), treasury);
        _whitelistRWA(address(rwa2), alice);
        vm.startPrank(bob);
        // transfer to alice so that only amountInRWA2 remains for bob
        ERC20(rwa2).transfer(alice, amount - amountInRWA2);
        assertEq(ERC20(address(rwa2)).balanceOf(bob), amountInRWA2);

        ERC20(address(rwa2)).approve(address(daoCollateral), amountInRWA2);
        // we swap amountInRWA of MMF for amount STBC
        daoCollateral.swap(address(rwa2), amountInRWA2, 0);
        vm.stopPrank();
        assertApproxEqRel(ERC20(address(stbc)).balanceOf(bob), amount, 0.00001 ether);
        // bob redeems his stbc for MMF
        vm.startPrank(bob);
        assertEq(ERC20(address(rwa2)).balanceOf(bob), 0);

        stbcBalance = ERC20(address(stbc)).balanceOf(bob);

        stbc.approve(address(daoCollateral), stbcBalance);
        uint256 bucketUsd0BalanceBefore = ERC20(address(stbc)).balanceOf(treasury);
        daoCollateral.redeem(address(rwa2), stbcBalance, 0);
        uint256 bucketAddedUsd0 = ERC20(address(stbc)).balanceOf(treasury) - bucketUsd0BalanceBefore;
        // fee is 0.1% and goes to treasury
        assertApproxEqRel(bucketAddedUsd0, _getDotOnePercent(amount), 0.001 ether);
        amountRedeemedMinusFee = stbcBalance - bucketAddedUsd0;
        // considering amount of $ find corresponding amount of MMF
        amountInRWA = (amountRedeemedMinusFee * 1e18) / classicalOracle.getPrice(address(rwa2));

        assertApproxEqRel(ERC20(address(rwa2)).balanceOf(bob), amountInRWA, 0.00000001 ether);
        // bob doesn't own STBC anymore
        assertEq(ERC20(address(stbc)).balanceOf(bob), 0);

        vm.stopPrank();
    }

    function testSwapRWA2CBROn() public returns (uint256) {
        (RwaMock rwa1, Usd0 stbc) = setupCreationRwa1_withMint(6, 100e18);
        (RwaMock rwa2,) = setupCreationRwa2_withMint(18, 100e18);
        deal(address(rwa1), treasury, 0);
        deal(address(rwa2), treasury, 0);

        // we swap amountInRWA of MMF for amount STBC
        vm.startPrank(alice);
        ERC20(rwa2).approve(address(daoCollateral), type(uint256).max);
        ERC20(rwa1).approve(address(daoCollateral), type(uint256).max);
        daoCollateral.swap(address(rwa1), 100e6, 100e18);
        daoCollateral.swap(address(rwa2), 100e18, 100e18);
        vm.stopPrank();
        assertEq(ERC20(address(stbc)).balanceOf(alice), 200e18);
        assertEq(ERC20(address(rwa1)).balanceOf(treasury), 100e6);
        assertEq(ERC20(address(rwa2)).balanceOf(treasury), 100e18);
        assertEq(stbc.balanceOf(usdInsurance), 0);
        assertEq(ERC20(address(stbc)).balanceOf(treasury), 0);

        // push RWA price to 0.5$
        vm.prank(admin);
        _setOraclePrice(address(rwa1), 0.5e6);
        assertEq(classicalOracle.getPrice(address(rwa1)), 0.5e18);

        // activate cbr
        assertEq(daoCollateral.cbrCoef(), 0);

        uint256 snapshot = vm.snapshot(); // saves the state
        vm.prank(admin);
        daoCollateral.activateCBR(0.75 ether); //0.75 ether

        assertEq(daoCollateral.cbrCoef(), 0.75 ether);

        vm.revertTo(snapshot); // restores the state
        assertEq(daoCollateral.cbrCoef(), 0);
        deal(address(rwa1), treasury, 62 ether);
        vm.prank(address(daoCollateral));
        stbc.mint(usdInsurance, 62 ether);
        assertEq(ERC20(address(stbc)).balanceOf(usdInsurance), 62 ether);
        assertEq(ERC20(address(stbc)).totalSupply(), 262 ether);
        uint256 firstCalcCoef =
            Math.mulDiv(212e18, SCALAR_ONE, ERC20(address(stbc)).totalSupply(), Math.Rounding.Floor);
        vm.prank(admin);
        daoCollateral.activateCBR(firstCalcCoef);
        // we have minted 200USD0 but only 0.5 *100 + 1 * 100 in collateral but as we also have 62e18 on
        // the insurance bucket can't mint because the USD0 totalSupply is 262 (62 + 150 -262)

        // push MMF price to 0.99$
        uint256 newPrice = 0.99e6;
        _setOraclePrice(address(rwa1), newPrice);
        assertEq(classicalOracle.getPrice(address(rwa1)), newPrice * 1e12);
        // we update the coef
        uint256 calcCoef = Math.mulDiv(
            100e18 + 100 * newPrice * 1e12 + 62e18,
            SCALAR_ONE,
            ERC20(address(stbc)).totalSupply(),
            Math.Rounding.Floor
        );
        vm.prank(admin);
        daoCollateral.activateCBR(calcCoef);
        assertEq(daoCollateral.cbrCoef(), calcCoef);
        assertGt(calcCoef, firstCalcCoef);

        // push MMF price back to 0.5$
        _setOraclePrice(address(rwa1), 0.5e6);
        assertEq(classicalOracle.getPrice(address(rwa1)), 0.5e18);
        // we update the coef
        vm.prank(admin);
        daoCollateral.activateCBR(firstCalcCoef);
        assertEq(daoCollateral.cbrCoef(), firstCalcCoef);

        // if we redeem rwa2 we redeem less than when cbr is off
        vm.startPrank(alice);
        // alice redeems his stbc for MMF

        assertEq(ERC20(address(rwa2)).balanceOf(alice), 0);

        uint256 stbcBalance = ERC20(address(stbc)).balanceOf(alice);

        stbc.approve(address(daoCollateral), stbcBalance);

        // we can't redeem all in rwa2
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                treasury,
                1e20,
                161_670_229_007_633_587_710
            )
        );

        daoCollateral.redeem(address(rwa2), stbcBalance, 0);
        // we only have the insurance bucket funds

        assertEq(ERC20(address(stbc)).balanceOf(usdInsurance), 62e18);

        uint256 amount = 25e18;
        daoCollateral.redeem(address(rwa2), amount, 0);
        uint256 stbcBalanceMinusFee = _getDotOnePercent(amount);
        uint256 amountRedeemedMinusFee = amount - stbcBalanceMinusFee;
        // considering amount of $ find corresponding amount of MMF
        uint256 amountInRWA =
            (amountRedeemedMinusFee * firstCalcCoef) / classicalOracle.getPrice(address(rwa2));
        assertApproxEqRel(ERC20(address(rwa2)).balanceOf(alice), amountInRWA, 0.00000001 ether);
        // alice doesn't own STBC anymore
        assertEq(ERC20(address(stbc)).balanceOf(alice), stbcBalance - amount);

        vm.stopPrank();
        return firstCalcCoef;
    }

    /*//////////////////////////////////////////////////////////////
                            5. REDEEM
    //////////////////////////////////////////////////////////////*/
    // 5.1 Testing revert properties //

    function testRedeemInvalidRwaFailEarly() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(InvalidToken.selector));
        daoCollateral.redeem(address(0xdeadbeef), 1e18, 0);
        vm.stopPrank();
    }

    function testRedeemForStableCoinFailAmount() public {
        (RwaMock token,) = testRWASwap(1e6);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        daoCollateral.redeem(address(token), 0, 0);
    }

    function testMultipleRedeemForStableCoinFailWhenNotEnoughCollateral() public {
        (RwaMock token,) = testRWASwap(1e6);

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, 1e18, 2e18
            )
        );
        daoCollateral.redeem(address(token), 2e18, 0);
        console.log("OK");
        daoCollateral.redeem(address(token), 1e18, 0);

        vm.stopPrank();
    }

    function testMultipleRedeemForStableCoinFail() public {
        (RwaMock token, Usd0 stbc) = testRWASwap(1e6);

        vm.startPrank(alice);
        daoCollateral.redeem(address(token), stbc.balanceOf(alice) - 0.5e18, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, 0.5e18, 1e18
            )
        );
        daoCollateral.redeem(address(token), 1e18, 0);
        daoCollateral.redeem(address(token), 0.5e18, 0);

        vm.stopPrank();
    }

    function testRedeemShouldFailIfMinAmountOut() public {
        (RwaMock token,) = testRWASwap(1e6);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AmountTooLow.selector));
        daoCollateral.redeem(address(token), 1e18, 1e6);
    }

    // 5.2 Testing basic flows //

    function testRedeemFiatWith6Decimals(uint256 amount) public {
        amount = bound(amount, 1_000_000, type(uint128).max - 1);
        (RwaMock token, Usd0 stbc) = testRWASwap(amount);

        vm.startPrank(alice);
        uint256 usd0Amount = stbc.balanceOf(alice);
        uint256 fee = _getDotOnePercent(amount);
        daoCollateral.redeem(address(token), usd0Amount, 0);
        vm.stopPrank();
        // The formula to calculate the amount of RWA that the user
        // should be able to get by redeeming STBC should be amountStableCoin * rwaDecimals / oraclePrice

        assertEq(stbc.balanceOf(alice), 0);
        assertApproxEqRel(token.balanceOf(alice), amount - fee, 0.00001 ether);
    }

    function testRedeemFiatFixAudit() public {
        (RwaMock token, Usd0 stbc) = setupCreationRwa1(6);

        deal(address(stbc), alice, 99_999_999_999_999);
        deal(address(token), address(treasury), 99);

        vm.prank(admin);
        // redeem fee 0.01 %
        daoCollateral.setRedeemFee(1);
        vm.prank(alice);

        // we redeem 0.000099999999999999 ETH
        // 0.01% is 10000000000 but 10000000000 / 1e12 (to make it on 6 decimals )= 0
        // the treasury is not allowed to own `stbc` tokens when no collateral exists
        daoCollateral.redeem(address(token), 99_999_999_999_999, 0);
        assertEq(IERC20(token).balanceOf(alice), 99);
        assertEq(IERC20(token).balanceOf(treasury), 0);
        assertEq(IERC20(stbc).balanceOf(treasury), 0);
    }

    function testRedeemFiatFixWithWadRwa() public {
        (RwaMock token, Usd0 stbc) = setupCreationRwa1(18);

        vm.prank(alice);
        assertEq(token.balanceOf(alice), 0);
        deal(address(stbc), alice, 99_999_999_999_999);
        deal(address(token), address(treasury), 99_999_999_999_999);

        vm.prank(admin);
        // redeem fee 0.01 %
        daoCollateral.setRedeemFee(1);
        vm.prank(alice);
        // we redeem 0.000099999999999999 ETH
        // 0.01% is 10000000000
        daoCollateral.redeem(address(token), 99_999_999_999_999, 0);
        assertEq(token.balanceOf(alice), 99_990_000_000_000);
        assertEq(IERC20(stbc).balanceOf(treasury), 9_999_999_999);
        assertEq(token.balanceOf(treasury), 9_999_999_999);
    }

    function testRedeemFiatWith27Decimals(uint256 amount) public {
        amount = bound(amount, 1_000_000_000_000, type(uint128).max - 1);
        (RwaMock token, Usd0 stbc) = testRWAWith27DecimalsSwap(amount);

        vm.startPrank(alice);
        uint256 usd0Amount = stbc.balanceOf(alice);
        uint256 amountInRWA = (usd0Amount * 1e27) / 1000e18;
        uint256 fee = _getDotOnePercent(amountInRWA);
        daoCollateral.redeem(address(token), usd0Amount, 0);
        vm.stopPrank();
        // The formula to calculate the amount of RWA that the user
        // should be able to get by redeeming STBC should be amountStableCoin * rwaDecimals / oraclePrice

        assertEq(stbc.balanceOf(alice), 0);
        assertApproxEqRel(token.balanceOf(alice), amountInRWA - fee, 0.00001 ether);
    }

    // solhint-disable-next-line max-states-count
    // swap 6 times "amount" of USYC => USD0
    // and try to redeem "amount" with only 5   USD0 => USYC to assert
    function testMultipleSwapAndRedeemForFiat(uint256 amount) public {
        amount = bound(amount, 320e6, (type(uint128).max) - 100e6 - 1);
        amount = amount - (amount % 32);
        uint256 wholeAmount = amount + 100e6;
        (RwaMock token, Usd0 stbc) = setupCreationRwa1_withMint(6, wholeAmount);

        vm.startPrank(alice);
        // multiple swap from USYC => USD0
        // will swap  for 1/2 of the amount
        uint256 amountToSwap1 = amount / 2;
        daoCollateral.swap(address(token), amountToSwap1, 0);

        // amount swap is rounded due to oracle price
        uint256 amountToSwap2 = amountToSwap1 / 2;
        // will swap for 1/4 of the amount
        daoCollateral.swap(address(token), amountToSwap2, 0);

        uint256 amountToSwap3 = amountToSwap2 / 2;
        // will swap for 1/8 of the amount
        daoCollateral.swap(address(token), amountToSwap3, 0);

        uint256 amountToSwap4 = amountToSwap3 / 2;
        // will swap for 1/16 of the amount
        daoCollateral.swap(address(token), amountToSwap4, 0);

        uint256 amountToSwap5 = amountToSwap4 / 2;
        // will swap for 1/32 of the amount
        daoCollateral.swap(address(token), amountToSwap5, 0);

        uint256 allFirst5 =
            amountToSwap1 + amountToSwap2 + amountToSwap3 + amountToSwap4 + amountToSwap5;
        // will swap for the remaining amount
        uint256 remainingAmount = (wholeAmount - allFirst5);
        daoCollateral.swap(address(token), remainingAmount, 0);
        vm.stopPrank();
        // Alice now has "wholeAmount" USD0 and 0 USYC
        assertEq(stbc.balanceOf(alice), wholeAmount * 1e12);
        assertEq(token.balanceOf(alice), wholeAmount - remainingAmount - allFirst5);

        // in total 6 swaps was done for Alice
        vm.startPrank(alice);
        stbc.approve(address(daoCollateral), allFirst5 * 1e12);
        assertEq(token.balanceOf(treasury), wholeAmount + remainingAmount + allFirst5);

        // USD0 => USYC
        // trying to redeem amountToSwap1 + amountToSwap2 + amountToSwap3 + amountToSwap4 + amountToSwap5

        daoCollateral.redeem(address(token), amountToSwap1 * 1e12, 0);
        daoCollateral.redeem(address(token), amountToSwap2 * 1e12, 0);
        daoCollateral.redeem(address(token), amountToSwap3 * 1e12, 0);
        daoCollateral.redeem(address(token), amountToSwap4 * 1e12, 0);
        daoCollateral.redeem(address(token), amountToSwap5 * 1e12, 0);

        vm.stopPrank();

        // Alice was only able to swap "allFirst5" amount of USD0 to USYC
        // she now has "remainingAmount" of USD0 and "returnedCollateral" USYC

        uint256 returnedCollateral = _getAmountMinusFeeInUSD(amountToSwap1, address(token));
        returnedCollateral += _getAmountMinusFeeInUSD(amountToSwap2, address(token));
        returnedCollateral += _getAmountMinusFeeInUSD(amountToSwap3, address(token));
        returnedCollateral += _getAmountMinusFeeInUSD(amountToSwap4, address(token));
        returnedCollateral += _getAmountMinusFeeInUSD(amountToSwap5, address(token));
        assertApproxEqRel(
            token.balanceOf(alice),
            wholeAmount - remainingAmount - allFirst5 + returnedCollateral,
            1e16
        );
        assertEq(stbc.balanceOf(alice), remainingAmount * 1e12);
        // the 0.1% fee in stable is sent to the treasury
        assertApproxEqRel(stbc.balanceOf(treasury), (allFirst5 - returnedCollateral) * 1e12, 1e16);
    }

    function testSwapWithRwaPriceFuzzFlow(uint256 oraclePrice) public {
        // uint256 oraclePrice = 10.2 ether;
        oraclePrice = bound(oraclePrice, 1e3, 1e12);
        uint256 rawAmount = 10_000e6;
        (RwaMock rwaToken, Usd0 stbc) = setupCreationRwa1_withMint(6, rawAmount);
        _setOraclePrice(address(rwaToken), oraclePrice);

        assertEq(classicalOracle.getPrice(address(rwaToken)), oraclePrice * 1e12);
        // considering amount of $ fin corresponding amount of MMF
        uint256 amountInRWA = (rawAmount * 1e18) / classicalOracle.getPrice(address(rwaToken));
        uint256 oracleQuote = classicalOracle.getQuote(address(rwaToken), amountInRWA);
        assertApproxEqRel(oracleQuote, rawAmount, ONE_PERCENT);

        _whitelistRWA(address(rwaToken), bob);
        rwaToken.mint(bob, amountInRWA);
        assertEq(ERC20(address(rwaToken)).balanceOf(bob), amountInRWA);

        vm.startPrank(bob);
        rwaToken.approve(address(daoCollateral), amountInRWA);
        // we swap amountInRWA of MMF for  amount STBC
        daoCollateral.swap(address(rwaToken), amountInRWA, 0);

        assertApproxEqRel(ERC20(address(stbc)).balanceOf(bob), rawAmount * 1e12, 0.0001 ether);
        assertEq(ERC20(address(rwaToken)).balanceOf(bob), 0);

        uint256 stbcBalance = ERC20(address(stbc)).balanceOf(bob);

        stbc.approve(address(daoCollateral), stbcBalance);

        daoCollateral.redeem(address(rwaToken), stbcBalance, 0);

        // fee is 0.1% and goes to treasury
        assertApproxEqRel(
            ERC20(address(stbc)).balanceOf(treasury),
            _getDotOnePercent(rawAmount * 1e12),
            0.0001 ether
        );
        uint256 amountRedeemedMinusFee = stbcBalance - ERC20(address(stbc)).balanceOf(treasury);
        // considering amount of $ find corresponding amount of MMF
        amountInRWA = (amountRedeemedMinusFee * 1e6) / classicalOracle.getPrice(address(rwaToken));
        assertApproxEqRel(ERC20(address(rwaToken)).balanceOf(bob), amountInRWA, 0.0002 ether);
        // bob doesn't own STBC anymore
        assertEq(ERC20(address(stbc)).balanceOf(bob), 0);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            6. REDEEM_DAO
    //////////////////////////////////////////////////////////////*/
    // 6.1 Testing revert properties //

    function testRedeemDaoShouldFailIfNotAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        daoCollateral.redeemDao(address(0x21), 1e18);
    }

    function testRedeemDaoShouldFailIfAmountZero() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        daoCollateral.redeemDao(address(0x21), 0);
        vm.stopPrank();
    }

    function testRedeemDaoShouldFailIfAmountTooLow() public {
        (RwaMock token, Usd0 stbc) = testRWASwap(1e18);

        vm.prank(alice);
        stbc.transfer(admin, 1e18);

        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(AmountTooLow.selector));
        daoCollateral.redeemDao(address(token), 1);
        vm.stopPrank();
    }

    function testRedeemDaoShouldFailIfInvalidToken() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(InvalidToken.selector));
        daoCollateral.redeemDao(address(0xdeadbeef), 1e18);
        vm.stopPrank();
    }

    // 6.2 Testing basic flows //

    function testRedeemDao() public {
        (RwaMock token, Usd0 stbc) = testRWASwap(1e6);
        _whitelistRWA(address(token), admin);

        vm.prank(alice);
        stbc.transfer(admin, 1e18);
        vm.prank(admin);
        daoCollateral.redeemDao(address(token), 1e18);

        assertEq(stbc.balanceOf(admin), 0);
        assertEq(token.balanceOf(admin), 1e6);
    }

    /*//////////////////////////////////////////////////////////////
              7. PAUSE, UNPAUSE, PAUSE_SWAP & UNPAUSE_SWAP
    //////////////////////////////////////////////////////////////*/
    // 7.1 Testing revert properties //

    function testUnpauseFailIfNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        daoCollateral.unpause();

        vm.prank(pauser);
        daoCollateral.pause();
        vm.prank(admin);
        daoCollateral.unpause();
    }

    function testUnpauseSwapFailIfNotPaused() public {
        vm.expectRevert(abi.encodeWithSelector(SwapMustBePaused.selector));
        vm.prank(admin);
        daoCollateral.unpauseSwap();
    }

    function testPauseSwapShouldFailIfPaused() public {
        vm.prank(pauser);
        daoCollateral.pauseSwap();
        assertEq(daoCollateral.isSwapPaused(), true);
        vm.expectRevert(abi.encodeWithSelector(SwapMustNotBePaused.selector));
        vm.prank(pauser);
        daoCollateral.pauseSwap();
    }

    function testPauseSwapRWAtoStbcIntentShouldFailIfPaused() public {
        vm.prank(pauser);
        daoCollateral.pauseSwap();

        uint256[] memory orderIdsToTake = new uint256[](1);

        vm.expectRevert(SwapMustNotBePaused.selector);
        daoCollateral.swapRWAtoStbcIntent(
            orderIdsToTake,
            Approval({deadline: block.timestamp + 100, v: 0, r: 0, s: 0}), // Dummy Approval, values don't matter
            Intent({ // Dummy Intent
                recipient: address(0),
                rwaToken: address(0),
                amountInTokenDecimals: 0,
                deadline: block.timestamp + 100,
                signature: bytes("0")
            }),
            false
        );
    }

    function testSwapRWAtoStbcShouldFailIfPaused() public {
        vm.prank(pauser);
        daoCollateral.pauseSwap();

        address rwaToken = address(0x123);
        uint256 amountInTokenDecimals = 1000;
        bool partialMatching = false;
        uint256[] memory orderIdsToTake = new uint256[](1);
        Approval memory approval =
            Approval({deadline: block.timestamp + 100, v: 0, r: bytes32(0), s: bytes32(0)});

        vm.expectRevert(SwapMustNotBePaused.selector);
        daoCollateral.swapRWAtoStbc(
            rwaToken, amountInTokenDecimals, partialMatching, orderIdsToTake, approval
        );
    }

    function testSwapShouldFailIfPaused() public {
        uint256 amount = 10_000_000_000;

        (RwaMock token,) = setupCreationRwa1_withMint(6, amount);

        vm.prank(pauser);
        daoCollateral.pause();
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(alice);
        daoCollateral.swap(address(token), amount, 0);
    }

    function testSwapWithPermitShouldFailIfPaused() public {
        uint256 amount = 10_000_000_000;
        (RwaMock token,) = setupCreationRwa1_withMint(6, amount);

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = _getAlicePermitData(
            block.timestamp + 100, address(token), address(daoCollateral), amount
        );

        vm.prank(pauser);
        daoCollateral.pause();
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(alice);
        daoCollateral.swapWithPermit(address(token), amount, amount, deadline, v, r, s);
    }

    // 7.2 Testing basic flows //

    function testPauseSwap() public {
        vm.prank(pauser);
        daoCollateral.pauseSwap();

        assertEq(daoCollateral.isSwapPaused(), true);
    }

    function testUnpauseSwap() public {
        vm.prank(pauser);
        daoCollateral.pauseSwap();

        vm.prank(admin);
        daoCollateral.unpauseSwap();
        assertEq(daoCollateral.isSwapPaused(), false);
    }

    function testGetSwapPaused() public {
        assertEq(daoCollateral.isSwapPaused(), false);
        vm.prank(pauser);
        daoCollateral.pauseSwap();
        assertEq(daoCollateral.isSwapPaused(), true);
    }

    /*//////////////////////////////////////////////////////////////
                    8. PAUSE_REDEEM & UNPAUSE_REDEEM
    //////////////////////////////////////////////////////////////*/
    // 8.1 Testing revert properties //

    function testRedeemShouldFailIfRedeemPaused() public {
        (RwaMock token,) = testRWASwap(1e6);

        vm.prank(pauser);
        daoCollateral.pauseRedeem();

        vm.expectRevert(abi.encodeWithSelector(RedeemMustNotBePaused.selector));
        vm.prank(alice);
        daoCollateral.redeem(address(token), 1e18, 0);
    }

    function testUnpauseRedeemShouldFailIfNotPaused() public {
        vm.expectRevert(abi.encodeWithSelector(RedeemMustBePaused.selector));
        vm.prank(admin);
        daoCollateral.unpauseRedeem();
    }

    function testRedeemShouldFailIfPaused() public {
        (RwaMock token,) = testRWASwap(100e6);

        vm.prank(pauser);
        daoCollateral.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(alice);
        daoCollateral.redeem(address(token), 100e18, 1e6);

        vm.prank(admin);
        daoCollateral.unpause();

        vm.prank(alice);
        daoCollateral.redeem(address(token), 100e18, 1e6);
    }

    function testUnPauseRedeemShouldFailIfNotAdmin() public {
        vm.prank(pauser);
        daoCollateral.pauseRedeem();

        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        daoCollateral.unpauseRedeem();
    }

    // 8.2 Testing basic flows //

    function testGetRedeemPaused() public {
        assertEq(daoCollateral.isRedeemPaused(), false);
        vm.prank(pauser);
        daoCollateral.pauseRedeem();
        assertEq(daoCollateral.isRedeemPaused(), true);

        vm.prank(admin);
        daoCollateral.unpauseRedeem();
        assertEq(daoCollateral.isRedeemPaused(), false);
    }

    function testUnPauseRedeemEmitEvent() public {
        vm.startPrank(pauser);
        daoCollateral.pauseRedeem();
        vm.expectEmit();
        emit RedeemUnPaused();
        vm.startPrank(admin);
        daoCollateral.unpauseRedeem();
    }

    /*//////////////////////////////////////////////////////////////
                            8. REDEEM_FEE
    //////////////////////////////////////////////////////////////*/
    // 9.1 Testing revert properties //

    function testSetRedeemFeeShouldFailIfSameValue() public {
        vm.prank(admin);
        daoCollateral.setRedeemFee(52);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        vm.prank(admin);
        daoCollateral.setRedeemFee(52);
    }

    function testSetRedeemFeeShouldFailIfAmountTooBig() public {
        vm.expectRevert(abi.encodeWithSelector(RedeemFeeTooBig.selector));
        vm.prank(admin);
        daoCollateral.setRedeemFee(MAX_REDEEM_FEE + 1);
    }

    function testSettersShouldFailIfNotAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        daoCollateral.setRedeemFee(MAX_REDEEM_FEE);
    }

    // 9.2 Testing basic flows //

    function testSetRedeemFee() public {
        vm.prank(admin);
        daoCollateral.setRedeemFee(52);
        assertEq(daoCollateral.redeemFee(), 52);
    }

    /*//////////////////////////////////////////////////////////////
                                9. CBR
    //////////////////////////////////////////////////////////////*/
    // 9.1 Testing revert properties //
    function testActivateCBRShouldFailIfItBenefitsMinter() public {
        (RwaMock rwa1, Usd0 stbc) = setupCreationRwa1_withMint(6, 100e6);
        (RwaMock rwa2,) = setupCreationRwa2_withMint(6, 100e6);

        vm.startPrank(alice);
        daoCollateral.swap(address(rwa1), 100e6, 100e18);
        daoCollateral.swap(address(rwa2), 100e6, 100e18);
        vm.stopPrank();

        // push MMF price to 0.5$
        _setOraclePrice(address(rwa1), 0.5e6);
        assertEq(classicalOracle.getPrice(address(rwa1)), 0.5e18);
        // increase rwa2 amount in treasury to make cbrCoef greater than
        IRwaMock(rwa2).mint(treasury, 1_000_000_000_000_000_000_000e6);
        // activate cbr
        assertEq(daoCollateral.cbrCoef(), 0);
        // increase usdBalanceInInsurance
        vm.prank(address(daoCollateral));
        stbc.mint(usdInsurance, 100e18);
        vm.expectRevert(abi.encodeWithSelector(CBRIsTooHigh.selector));
        vm.prank(admin);
        daoCollateral.activateCBR(5e18);
        assertFalse(daoCollateral.isCBROn());
        assertEq(daoCollateral.cbrCoef(), 0);
    }

    function testActivateCBRShouldFailIfCBRisTooHigh() public {
        (RwaMock rwa1, Usd0 stbc) = setupCreationRwa1_withMint(6, 100e6);
        (RwaMock rwa2,) = setupCreationRwa2_withMint(6, 100e6);

        vm.startPrank(alice);
        // we swap amountInRWA of MMF for amount STBC
        daoCollateral.swap(address(rwa1), 100e6, 100e18);
        daoCollateral.swap(address(rwa2), 100e6, 100e18);
        vm.stopPrank();

        assertEq(stbc.balanceOf(usdInsurance), 0);
        assertEq(ERC20(address(stbc)).balanceOf(treasury), 0);

        // push MMF price to 0.5$
        _setOraclePrice(address(rwa1), 0.5e6);

        // burn all rwa1 and rwa2 in treasury to make cbrCoef equal to 0
        IRwaMock(rwa2).burnFrom(treasury, IRwaMock(rwa2).balanceOf(treasury));
        IRwaMock(rwa1).burnFrom(treasury, IRwaMock(rwa1).balanceOf(treasury));

        // activate cbr
        assertEq(daoCollateral.cbrCoef(), 0);
        vm.expectRevert(abi.encodeWithSelector(CBRIsNull.selector));
        vm.prank(admin);
        daoCollateral.activateCBR(0); //0
        assertFalse(daoCollateral.isCBROn());
        assertEq(daoCollateral.cbrCoef(), 0);
    }

    function testDeactivateCBRShouldFailIfNotActive() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        daoCollateral.deactivateCBR();
    }

    // 9.2 Testing basic flows //

    function testRoundingInCbrCoefCalculation() public pure {
        uint256 wadTotalRwaValueInUsd = 100e18 - 1;
        uint256 totalUsdSupply = 100e18;
        uint256 price = Math.mulDiv(wadTotalRwaValueInUsd, SCALAR_ONE, 100e18);
        uint256 price2 = Math.mulDiv(100e18 - 100, SCALAR_ONE, 100e18);

        assertEq(price, price2);
        uint256 cbrCoef_Floor =
            Math.mulDiv(wadTotalRwaValueInUsd, SCALAR_ONE, totalUsdSupply, Math.Rounding.Floor);

        uint256 cbrCoef_Ceil =
            Math.mulDiv(wadTotalRwaValueInUsd, SCALAR_ONE, totalUsdSupply, Math.Rounding.Ceil);
        assertLt(cbrCoef_Floor, cbrCoef_Ceil); // we should lean toward cbrCoef_Floor
            // 999999999999999999 < 1000000000000000000
    }

    function testDeactivateCBR() public {
        vm.startPrank(admin);

        // activate cbr
        daoCollateral.activateCBR(1);

        vm.expectEmit();
        emit CBRDeactivated();
        daoCollateral.deactivateCBR();
        assertFalse(daoCollateral.isCBROn());
    }

    /*//////////////////////////////////////////////////////////////
                      10. SWAP_RWA_TO_STBC_INTENT
    //////////////////////////////////////////////////////////////*/
    // 10.1 Testing revert properties //

    function testSwapRWAtoStbcIntent_RevertsIfNotIntentMatcherRole() public {
        uint256 amount = 42_000 * 1e6;
        uint256 deadline = block.timestamp + 100;
        (RwaMock rwaToken,) = setupCreationRwa1_withMint(6, amount);
        (Intent memory intent, uint256[] memory orderIdsToTake, Approval memory approval) =
        setupSwapRWAtoStbcIntent_withDeposit(
            alice, address(rwaToken), address(rwaToken), deadline, deadline
        );
        vm.prank(admin);
        registryAccess.revokeRole(INTENT_MATCHING_ROLE, alice);
        vm.prank(alice);

        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        daoCollateral.swapRWAtoStbcIntent(orderIdsToTake, approval, intent, true);
    }

    function testSwapRWAtoStbcIntent_RevertsIfNonceInvalidated() public {
        uint256 amount = 42_000 * 1e6;
        uint256 deadline = block.timestamp + 100;
        (RwaMock rwaToken,) = setupCreationRwa1_withMint(6, amount);
        (Intent memory intent, uint256[] memory orderIdsToTake, Approval memory approval) =
        setupSwapRWAtoStbcIntent_withDeposit(
            alice, address(rwaToken), address(rwaToken), deadline, deadline
        );

        vm.prank(alice);
        daoCollateral.invalidateNonce();

        vm.prank(alice);

        //@notice this currently reverts as invalid signer instead, since the recovered hash doesn't match the signed nonce, since we are using the latest valid nonce
        //vm.expectRevert(abi.encodeWithSelector(InvalidAccountNonce.selector, alice, intentNonce));
        vm.expectRevert();
        daoCollateral.swapRWAtoStbcIntent(orderIdsToTake, approval, intent, true);
    }

    function testSwapRWAtoStbcIntent_RevertsIfSwapperEngineIsEmpty() public {
        uint256 amount = 42_000 * 1e6;
        uint256 deadline = block.timestamp + 100;
        (RwaMock rwaToken,) = setupCreationRwa1_withMint(6, amount);
        (Intent memory intent, uint256[] memory orderIdsToTake, Approval memory approval) =
        setupSwapRWAtoStbcIntent_withoutDeposit(
            alice, address(rwaToken), address(rwaToken), deadline, deadline
        );

        vm.expectRevert(abi.encodeWithSelector(AmountTooLow.selector));
        vm.prank(alice);
        daoCollateral.swapRWAtoStbcIntent(orderIdsToTake, approval, intent, true);
    }

    function testSwapRWAtoStbcIntent_RevertsWithInvalidIntentRecipient() public {
        uint256 amount = 42_000 * 1e6;
        uint256 deadline = block.timestamp + 100;
        (RwaMock rwaToken,) = setupCreationRwa1_withMint(6, amount);
        (Intent memory intent, uint256[] memory orderIdsToTake, Approval memory approval) =
        setupSwapRWAtoStbcIntent_withDeposit(
            address(0xdeadbeef), address(rwaToken), address(rwaToken), deadline, deadline
        );

        vm.expectRevert(abi.encodeWithSelector(InvalidSigner.selector, address(0xdeadbeef)));
        vm.prank(alice);
        daoCollateral.swapRWAtoStbcIntent(orderIdsToTake, approval, intent, true);
    }

    function testSwapRWAtoStbcIntent_RevertsWithExpiredSignature() public {
        uint256 amount = 42_000 * 1e6;
        uint256 deadline = block.timestamp + 100;
        (RwaMock rwaToken,) = setupCreationRwa1_withMint(6, amount);
        (Intent memory intent, uint256[] memory orderIdsToTake, Approval memory approval) =
        setupSwapRWAtoStbcIntent_withDeposit(
            alice, address(rwaToken), address(rwaToken), block.timestamp - 100, deadline
        );

        vm.expectRevert(abi.encodeWithSelector(ExpiredSignature.selector, block.timestamp - 100));
        vm.prank(alice);
        daoCollateral.swapRWAtoStbcIntent(orderIdsToTake, approval, intent, true);
    }

    function testSwapRWAtoStbcIntent_RevertsWithMismatchedIntentApprovalDeadlines() public {
        uint256 amount = 42_000 * 1e6;
        uint256 deadline = block.timestamp + 101;
        (RwaMock rwaToken,) = setupCreationRwa1_withMint(6, amount);
        (Intent memory intent, uint256[] memory orderIdsToTake, Approval memory approval) =
        setupSwapRWAtoStbcIntent_withDeposit(
            alice, address(rwaToken), address(rwaToken), block.timestamp + 200, deadline
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidDeadline.selector, block.timestamp + 100, block.timestamp + 200
            )
        );
        vm.prank(alice);
        daoCollateral.swapRWAtoStbcIntent(orderIdsToTake, approval, intent, true);
    }

    function testSwapRWAtoStbcIntent_RevertsIfInvalidRwaTokenIsGiven() public {
        uint256 amount = 42_000 * 1e6;
        uint256 deadline = block.timestamp + 100;
        (RwaMock rwaToken,) = setupCreationRwa1_withMint(6, amount);
        (Intent memory intent, uint256[] memory orderIdsToTake, Approval memory approval) =
        setupSwapRWAtoStbcIntent_withDeposit(
            alice, address(rwaToken), address(0xdeadbeef), deadline, deadline
        );

        vm.expectRevert(abi.encodeWithSelector(InvalidToken.selector));
        vm.prank(alice);
        daoCollateral.swapRWAtoStbcIntent(orderIdsToTake, approval, intent, true);
    }

    // 10.2 Testing basic flows //

    function testSwapRWAtoStbcIntent() public {
        uint256 amount = 42_000 * 1e6;
        uint256 deadline = block.timestamp + 100;
        (RwaMock rwaToken,) = setupCreationRwa1_withMint(6, amount);
        (Intent memory intent, uint256[] memory orderIdsToTake, Approval memory approval) =
        setupSwapRWAtoStbcIntent_withDeposit(
            alice, address(rwaToken), address(rwaToken), deadline, deadline
        );

        vm.prank(alice);
        vm.expectEmit();
        emit Swap(alice, address(rwaToken), intent.amountInTokenDecimals, amount * 1e12);
        daoCollateral.swapRWAtoStbcIntent(orderIdsToTake, approval, intent, true);
    }

    uint256 constant BASE_AMOUNT = 1e18; // 1 RWA token (18 decimals)
    uint256 constant TOTAL_AMOUNT = 4000 * BASE_AMOUNT; // 1000 RWA tokens
    uint256 constant PARTIAL_AMOUNT = 1000 * BASE_AMOUNT; // 250 RWA tokens
    uint256 constant NONCE_THRESHOLD = 1 * BASE_AMOUNT; // 100 RWA tokens
    uint256 constant MIN_USDC_DEPOSIT = 1000 * 1e6; // 1000 USDC (6 decimals)

    function setupTest(uint256 rwaAmount)
        internal
        returns (RwaMock, Intent memory, Approval memory)
    {
        (RwaMock rwaToken,) = setupCreationRwa1(18);
        rwaToken.mint(alice, rwaAmount);
        _setOraclePrice(address(rwaToken), 1e18); // Set RWA token price to $1

        deal(address(rwaToken), treasury, type(uint128).max);

        uint256 deadline = block.timestamp + 1 hours;

        Intent memory intent = Intent({
            recipient: alice,
            rwaToken: address(rwaToken),
            amountInTokenDecimals: rwaAmount,
            deadline: deadline,
            signature: bytes("")
        });

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: alice,
            spender: address(daoCollateral),
            value: type(uint256).max,
            nonce: IERC20Permit(address(rwaToken)).nonces(alice),
            deadline: deadline
        });

        uint256 intentNonce = daoCollateral.nonces(intent.recipient);
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                daoCollateral.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        INTENT_TYPE_HASH,
                        intent.recipient,
                        intent.rwaToken,
                        intent.amountInTokenDecimals,
                        intentNonce,
                        intent.deadline
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivKey, digest);
        intent.signature = abi.encodePacked(r, s, v);

        Approval memory approval = Approval({deadline: deadline, v: 0, r: 0, s: 0});
        SigUtils sigUtils = new SigUtils(IERC20Permit(address(rwaToken)).DOMAIN_SEPARATOR());
        (approval.v, approval.r, approval.s) =
            vm.sign(alicePrivKey, sigUtils.getTypedDataHash(permit));

        return (rwaToken, intent, approval);
    }

    function setupUsdcOrders(uint256[] memory orderAmounts) internal returns (uint256[] memory) {
        uint256[] memory orderIds = new uint256[](orderAmounts.length);
        uint256 usdcWadPrice = _getUsdcWadPrice();

        for (uint256 i = 0; i < orderAmounts.length; i++) {
            uint256 usdcDepositAmount =
                _getUsdcAmountFromUsd0WadEquivalent(orderAmounts[i], usdcWadPrice);

            vm.startPrank(bob);
            deal(address(USDC), bob, usdcDepositAmount);
            IUSDC(address(USDC)).approve(address(swapperEngine), usdcDepositAmount);
            orderIds[i] = i + 1;
            swapperEngine.depositUSDC(usdcDepositAmount);
            vm.stopPrank();

            (bool active,) = swapperEngine.getOrder(orderIds[i]);
            require(active, "Order not created successfully");
        }

        return orderIds;
    }

    function testAtomicFullMatch() public {
        (RwaMock rwaToken, Intent memory intent, Approval memory approval) = setupTest(TOTAL_AMOUNT);
        uint256[] memory orderAmounts = new uint256[](1);
        orderAmounts[0] = TOTAL_AMOUNT;
        uint256[] memory orderIds = setupUsdcOrders(orderAmounts);

        uint256 initialNonce = daoCollateral.nonces(alice);

        vm.expectEmit(true, true, true, true);
        emit Swap(alice, address(rwaToken), TOTAL_AMOUNT, TOTAL_AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit IntentMatched(alice, initialNonce, address(rwaToken), TOTAL_AMOUNT, TOTAL_AMOUNT);

        vm.prank(alice);
        daoCollateral.swapRWAtoStbcIntent(orderIds, approval, intent, false);

        assertEq(
            daoCollateral.nonces(alice), initialNonce + 1, "Nonce should increment after full match"
        );
        assertEq(
            daoCollateral.orderAmountTakenCurrentNonce(alice),
            0,
            "Order amount should reset after full match"
        );
    }

    function testPartialMatch() public {
        (RwaMock rwaToken, Intent memory intent, Approval memory approval) = setupTest(TOTAL_AMOUNT);
        uint256[] memory orderAmounts = new uint256[](1);
        orderAmounts[0] = PARTIAL_AMOUNT;
        uint256[] memory orderIds = setupUsdcOrders(orderAmounts);

        uint256 initialNonce = daoCollateral.nonces(alice);

        vm.expectEmit(true, true, true, true);
        emit Swap(alice, address(rwaToken), PARTIAL_AMOUNT, PARTIAL_AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit IntentMatched(alice, initialNonce, address(rwaToken), PARTIAL_AMOUNT, PARTIAL_AMOUNT);

        vm.prank(alice);
        daoCollateral.swapRWAtoStbcIntent(orderIds, approval, intent, true);

        assertEq(
            daoCollateral.nonces(alice),
            initialNonce,
            "Nonce should not increment after partial match"
        );
        assertEq(
            daoCollateral.orderAmountTakenCurrentNonce(alice),
            PARTIAL_AMOUNT,
            "Incorrect amount taken"
        );
    }

    function testSequentialPartialMatches() public {
        (RwaMock rwaToken, Intent memory intent, Approval memory approval) = setupTest(TOTAL_AMOUNT);
        uint256[] memory orderAmounts = new uint256[](4);
        orderAmounts[0] = PARTIAL_AMOUNT;
        orderAmounts[1] = PARTIAL_AMOUNT;
        orderAmounts[2] = PARTIAL_AMOUNT;
        orderAmounts[3] = PARTIAL_AMOUNT;

        uint256[] memory allOrderIds = setupUsdcOrders(orderAmounts);
        uint256 initialNonce = daoCollateral.nonces(alice);
        uint256 totalAmountTaken = 0;

        for (uint256 i = 0; i < 4; i++) {
            uint256[] memory currentOrderId = new uint256[](1);
            currentOrderId[0] = allOrderIds[i];

            // Check the amount of the current order is active
            (bool active,) = swapperEngine.getOrder(currentOrderId[0]);
            require(active, "Order is not active");

            if (i < 3) {
                assertEq(
                    daoCollateral.nonces(alice),
                    initialNonce,
                    "Nonce should not increment after partial match"
                );
                assertEq(
                    daoCollateral.orderAmountTakenCurrentNonce(alice),
                    totalAmountTaken,
                    "Incorrect amount taken"
                );
                vm.prank(alice);
                daoCollateral.swapRWAtoStbcIntent(currentOrderId, approval, intent, true);

                totalAmountTaken += PARTIAL_AMOUNT;
            } else if (i == 3) {
                assertEq(
                    daoCollateral.nonces(alice),
                    initialNonce,
                    "Nonce should not increment after partial match"
                );
                assertEq(
                    daoCollateral.orderAmountTakenCurrentNonce(alice),
                    totalAmountTaken,
                    "Incorrect amount taken"
                );
                vm.prank(alice);
                vm.expectEmit(true, true, true, true);
                emit IntentConsumed(
                    alice, initialNonce, address(rwaToken), intent.amountInTokenDecimals
                );
                daoCollateral.swapRWAtoStbcIntent(currentOrderId, approval, intent, true);

                totalAmountTaken += PARTIAL_AMOUNT;
            } else {
                assertEq(
                    daoCollateral.nonces(alice),
                    initialNonce + 1,
                    "Nonce should increment after full match"
                );
                assertEq(
                    daoCollateral.orderAmountTakenCurrentNonce(alice),
                    0,
                    "Amount taken should reset after full match"
                );
            }
        }
    }

    function testNonceThresholdBehavior() public {
        // Setup
        (RwaMock rwaToken, Intent memory intent, Approval memory approval) = setupTest(TOTAL_AMOUNT);
        vm.prank(alice);
        IERC20(address(rwaToken)).approve(address(daoCollateral), type(uint256).max);

        // Test setting nonce threshold
        uint256 validThreshold = 1e17; // 0.1 * 1e18 (10 cents)
        vm.prank(admin);
        registryAccess.grantRole(NONCE_THRESHOLD_SETTER_ROLE, carol);
        vm.prank(carol);
        daoCollateral.setNonceThreshold(validThreshold);
        assertEq(
            daoCollateral.nonceThreshold(), validThreshold, "Nonce threshold not set correctly"
        );

        // Test setting threshold by non-admin
        vm.prank(alice);
        vm.expectRevert(); // Expect revert due to lack of admin role
        daoCollateral.setNonceThreshold(validThreshold);

        // Create orders
        uint256 tenCents = 1e17; // 0.1 * 1e18
        uint256[] memory orderAmounts = new uint256[](2);
        orderAmounts[0] = TOTAL_AMOUNT / 2; // First half
        orderAmounts[1] = TOTAL_AMOUNT - (orderAmounts[0] + tenCents); // Leave exactly 10 cents remaining

        uint256[] memory orderIds = setupUsdcOrders(orderAmounts);
        uint256 initialNonce = daoCollateral.nonces(alice);

        // Execute first order
        uint256[] memory orderOne = new uint256[](1);
        orderOne[0] = orderIds[0];
        vm.prank(alice);
        daoCollateral.swapRWAtoStbcIntent(orderOne, approval, intent, true);
        assertEq(
            daoCollateral.nonces(alice),
            initialNonce,
            "Nonce should not increment after first order"
        );
        assertEq(
            daoCollateral.orderAmountTakenCurrentNonce(alice),
            orderAmounts[0],
            "Incorrect amount taken after first order"
        );

        // Execute second order
        uint256[] memory orderTwo = new uint256[](1);
        orderTwo[0] = orderIds[1];
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IntentConsumed(alice, initialNonce, address(rwaToken), intent.amountInTokenDecimals);
        daoCollateral.swapRWAtoStbcIntent(orderTwo, approval, intent, true);
        assertEq(
            daoCollateral.nonces(alice),
            initialNonce + 1,
            "Nonce should increment after second order"
        );
        assertEq(
            daoCollateral.orderAmountTakenCurrentNonce(alice),
            0,
            "Amount taken should reset after second order"
        );
    }
    /*//////////////////////////////////////////////////////////////
                        11. SWAP_RWA_TO_STBC
    //////////////////////////////////////////////////////////////*/
    // 11.1 Testing revert properties //

    function testSwapRWAtoStbc_RevertsIfZeroAmountIsGiven() public {
        (RwaMock rwaToken,) = setupCreationRwa1(6);

        uint256[] memory orderIdsToTake;
        Approval memory approval;

        vm.expectRevert(AmountIsZero.selector);
        vm.prank(alice);
        daoCollateral.swapRWAtoStbc(address(rwaToken), 0, true, orderIdsToTake, approval);
    }

    function testSwapRWAtoStbc_RevertsIfAmountTooBigIsGiven() public {
        (RwaMock rwaToken,) = setupCreationRwa1(6);

        uint256[] memory orderIdsToTake;
        Approval memory approval;

        uint256 amountTooBig = type(uint128).max;
        ++amountTooBig;
        vm.expectRevert(AmountTooBig.selector);
        vm.prank(alice);
        daoCollateral.swapRWAtoStbc(address(rwaToken), amountTooBig, true, orderIdsToTake, approval);
    }

    function testSwapRWAtoStbc_RevertsIfNoOrderIdsAreGiven() public {
        (RwaMock rwaToken,) = setupCreationRwa1(6);

        uint256[] memory emptyOrderIdArray;
        Approval memory approval;

        vm.expectRevert(NoOrdersIdsProvided.selector);
        vm.prank(alice);
        daoCollateral.swapRWAtoStbc(address(rwaToken), 42, true, emptyOrderIdArray, approval);
    }

    function testSwapRWAtoStbc_RevertsIfInvalidRwaTokenIsGiven() public {
        uint256[] memory orderIdsToTake = new uint256[](2);
        Approval memory approval;

        vm.expectRevert(InvalidToken.selector);
        vm.prank(alice);
        daoCollateral.swapRWAtoStbc(address(0xdeadbeef), 42, true, orderIdsToTake, approval);
    }

    function testSwapRWAtoStbc_RevertsIfSwapperEngineIsEmpty() public {
        uint256 numOrders = 2;
        uint256 amount = 42;

        (RwaMock rwaMock,) = setupCreationRwa1_withMint(6, amount);
        address rwaToken = address(rwaMock);

        /**
         * inputs
         */
        uint256[] memory orderIdsToTake = new uint256[](numOrders);
        orderIdsToTake[0] = 1;
        orderIdsToTake[1] = 2;

        Approval memory approval = Approval({deadline: block.timestamp + 100, v: 0, r: 0, s: 0});
        SigUtils sigUtils = new SigUtils(IERC20Permit(rwaToken).DOMAIN_SEPARATOR());
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: alice,
            spender: address(daoCollateral),
            value: amount,
            nonce: IERC20Permit(rwaToken).nonces(alice),
            deadline: approval.deadline
        });
        (approval.v, approval.r, approval.s) =
            vm.sign(alicePrivKey, sigUtils.getTypedDataHash(permit));
        vm.mockCall(
            address(classicalOracle),
            abi.encodeWithSelector(IOracle.getPrice.selector, rwaToken),
            abi.encode(1e18)
        );

        vm.expectRevert(abi.encodeWithSelector(AmountTooLow.selector));
        vm.prank(alice);
        daoCollateral.swapRWAtoStbc(rwaToken, amount, true, orderIdsToTake, approval);
    }

    function testSwapRWAtoStbc_RevertsIfApprovalFailed() public {
        uint256 amountInUsd0 = 42_000 * 1e18;
        uint256 amountToDeposit =
            _getUsdcAmountFromUsd0WadEquivalent(amountInUsd0, _getUsdcWadPrice());
        (
            RwaMock rwaToken,
            uint256 rwaAmount,
            uint256[] memory orderIdsToTake,
            Approval memory approval
        ) = setupSwapRWAToStbc_withDeposit(amountToDeposit);

        vm.prank(alice);
        vm.mockCall(
            address(stbcToken), abi.encodeWithSelector(IERC20.approve.selector), abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(ApprovalFailed.selector));
        daoCollateral.swapRWAtoStbc(address(rwaToken), rwaAmount, true, orderIdsToTake, approval);
    }

    // 11.2 Testing basic flow //

    function testSwapRWAtoStbc() public {
        uint256 amountInUsd0 = 42_000 * 1e18;
        uint256 amountToDeposit =
            _getUsdcAmountFromUsd0WadEquivalent(amountInUsd0, _getUsdcWadPrice());
        (
            RwaMock rwaToken,
            uint256 rwaAmount,
            uint256[] memory orderIdsToTake,
            Approval memory approval
        ) = setupSwapRWAToStbc_withDeposit(amountToDeposit);

        vm.prank(alice);
        daoCollateral.swapRWAtoStbc(address(rwaToken), rwaAmount, true, orderIdsToTake, approval);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), 0);
        assertEq(IUSDC(address(USDC)).balanceOf(alice), amountToDeposit);
    }

    function testSwapRWAtoStbcWithNullApproval() public {
        uint256 amountInUsd0 = 42_000 * 1e18;
        uint256 amountToDeposit =
            _getUsdcAmountFromUsd0WadEquivalent(amountInUsd0, _getUsdcWadPrice());
        (RwaMock rwaToken, uint256 rwaAmount, uint256[] memory orderIdsToTake,) =
            setupSwapRWAToStbc_withDeposit(amountToDeposit);

        Approval memory approval = Approval({deadline: 0, v: 0, r: 0, s: 0});

        vm.startPrank(alice);
        daoCollateral.swapRWAtoStbc(address(rwaToken), rwaAmount, true, orderIdsToTake, approval);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), 0);
        assertEq(IUSDC(address(USDC)).balanceOf(alice), amountToDeposit);
    }

    function testSwapRWAtoStbc_SwapperEnginePartiallyFull() public {
        uint256 amountInUsd0 = 42_000 * 1e18;
        uint256 amountToDeposit =
            _getUsdcAmountFromUsd0WadEquivalent(amountInUsd0, _getUsdcWadPrice());
        (
            RwaMock rwaToken,
            uint256 rwaAmount,
            uint256[] memory orderIdsToTake,
            Approval memory approval
        ) = setupSwapRWAToStbc_withDeposit(amountToDeposit / 2);

        vm.prank(alice);
        daoCollateral.swapRWAtoStbc(address(rwaToken), rwaAmount, true, orderIdsToTake, approval);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), 0);
        assertEq(IUSDC(address(USDC)).balanceOf(alice), amountToDeposit / 2);
    }

    function testRealizeImpermanentLossOk() public {
        (RwaMock rwa1, Usd0 stbc) = setupCreationRwa1_withMint(18, 100e18);
        deal(address(rwa1), treasury, 0);
        vm.prank(alice);
        daoCollateral.swap(address(rwa1), 100e18, 0);

        // Update oracle price
        _setOraclePrice(address(rwa1), 1e18 - 1);
        assertEq(classicalOracle.getPrice(address(rwa1)), 1e18 - 1);

        // Verify expected totalRWAValueInUSD
        uint8 decimals = ERC20(address(rwa1)).decimals();
        assertEq(decimals, 18);
        uint256 tokenAmount = ERC20(address(rwa1)).balanceOf(treasury);
        uint256 wadAmount = Normalize.tokenAmountToWad(tokenAmount, decimals);
        uint256 wadPriceInUSD = uint256(classicalOracle.getPrice(address(rwa1)));
        uint256 totalRWAValueInUSD =
            Math.mulDiv(wadAmount, wadPriceInUSD, SCALAR_ONE, Math.Rounding.Ceil);
        assertEq(totalRWAValueInUSD, 100e18 - 100); // precision loss

        // Activate and check cbr coefficient
        uint256 firstCalcCoefFloor = Math.mulDiv(
            totalRWAValueInUSD, // Total RWA value in USD
            SCALAR_ONE, // SCALAR_ONE assumed to be 1e18 for scaling
            ERC20(address(stbc)).totalSupply(),
            Math.Rounding.Floor // Adjusted to Floor to prevent overestimation
        );

        uint256 firstCalcCoefCeil = Math.mulDiv(
            totalRWAValueInUSD, // Total RWA value in USD
            SCALAR_ONE, // SCALAR_ONE assumed to be 1e18 for scaling
            ERC20(address(stbc)).totalSupply(),
            Math.Rounding.Ceil // Adjusted to Floor to prevent overestimation
        );
        vm.prank(admin);
        daoCollateral.activateCBR(firstCalcCoefFloor);
        assertEq(firstCalcCoefFloor, firstCalcCoefCeil);

        vm.prank(admin);
        daoCollateral.setRedeemFee(0);
        assertEq(daoCollateral.redeemFee(), 0);

        vm.prank(alice);
        // Should not revert
        daoCollateral.redeem(address(rwa1), 100e18, 0);
        assertEq(ERC20(address(rwa1)).balanceOf(alice), 100e18 - 1);
        assertEq(ERC20(address(rwa1)).balanceOf(treasury), 1);
    }

    /*//////////////////////////////////////////////////////////////
                           12. SET_ROLE_ADMIN
    //////////////////////////////////////////////////////////////*/

    function testSetRoleAdmin() public {
        vm.startPrank(admin);

        registryAccess.grantRole(INTENT_MATCHING_ROLE, bob);
        assertTrue(registryAccess.hasRole(INTENT_MATCHING_ROLE, bob));
        registryAccess.revokeRole(INTENT_MATCHING_ROLE, bob);
        assertFalse(registryAccess.hasRole(INTENT_MATCHING_ROLE, bob));
    }

    /*//////////////////////////////////////////////////////////////
                          13. INVALIDATE_NONCE
    //////////////////////////////////////////////////////////////*/

    function testInvalidateNonce() public {
        uint256 initialNonce = daoCollateral.nonces(alice);
        assertEq(initialNonce, 0, "Initial nonce should be 0");

        // invalidate nonce as alice
        vm.startPrank(alice);
        vm.expectEmit(true, true, false, true);
        emit NonceInvalidated(alice, initialNonce);
        daoCollateral.invalidateNonce();
        vm.stopPrank();

        // Check nonce after invalidation
        uint256 newNonce = daoCollateral.nonces(alice);
        assertEq(newNonce, initialNonce + 1, "Nonce should be incremented by 1");

        // invalidate nonce again and check event
        vm.startPrank(alice);
        vm.expectEmit(true, true, false, true);
        emit NonceInvalidated(alice, newNonce);
        daoCollateral.invalidateNonce();
        vm.stopPrank();

        // check nonce after second invalidation
        uint256 finalNonce = daoCollateral.nonces(alice);
        assertEq(finalNonce, newNonce + 1, "Nonce should be incremented by 1 again");
    }

    function testInvalidateUpToNonce_InvalidateToHigherValue() public {
        uint256 initialNonce = daoCollateral.nonces(alice);
        uint256 newNonce = initialNonce + 1;

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit NonceInvalidated(alice, newNonce - 1);
        daoCollateral.invalidateUpToNonce(newNonce);

        uint256 updatedNonce = daoCollateral.nonces(alice);
        assertEq(updatedNonce, newNonce, "Nonce should be incremented to the new value");
    }

    function testInvalidateUpToNonce_InvalidateToLowerValue() public {
        uint256 initialNonce = daoCollateral.nonces(alice);
        uint256 lowerNonce = initialNonce;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(InvalidAccountNonce.selector, alice, lowerNonce));
        daoCollateral.invalidateUpToNonce(lowerNonce);
    }

    function testInvalidateUpToNonce_InvalidateToSameValue() public {
        uint256 initialNonce = daoCollateral.nonces(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(InvalidAccountNonce.selector, alice, initialNonce));
        daoCollateral.invalidateUpToNonce(initialNonce);
    }

    function testInvalidateUpToNonce_MultipleInvalidations() public {
        uint256 initialNonce = daoCollateral.nonces(alice);
        uint256 newNonce1 = initialNonce + 1;
        uint256 newNonce2 = newNonce1 + 1;

        vm.startPrank(alice);
        daoCollateral.invalidateUpToNonce(newNonce1);
        daoCollateral.invalidateUpToNonce(newNonce2);
        vm.stopPrank();

        uint256 finalNonce = daoCollateral.nonces(alice);
        assertEq(finalNonce, newNonce2, "Nonce should be updated to the latest value");
    }

    function testInvalidateUpToNonce_InvalidateByDifferentUsers() public {
        uint256 initialNonceAlice = daoCollateral.nonces(alice);
        uint256 initialNonceBob = daoCollateral.nonces(bob);

        vm.prank(alice);
        daoCollateral.invalidateUpToNonce(initialNonceAlice + 1);

        vm.prank(bob);
        daoCollateral.invalidateUpToNonce(initialNonceBob + 2);

        uint256 finalNonceAlice = daoCollateral.nonces(alice);
        uint256 finalNonceBob = daoCollateral.nonces(bob);

        assertEq(finalNonceAlice, initialNonceAlice + 1, "Alice's nonce should be updated");
        assertEq(finalNonceBob, initialNonceBob + 2, "Bob's nonce should be updated");
    }

    function testInvalidateUpToNonce_InvalidateZeroNonce() public {
        uint256 initialNonce = 0;

        vm.prank(alice);
        daoCollateral.invalidateUpToNonce(initialNonce + 1);

        uint256 finalNonce = daoCollateral.nonces(alice);
        assertEq(finalNonce, initialNonce + 1, "Nonce should be incremented from zero");
    }

    function testInvalidateUpToNonce_InvalidateMaxNonce() public {
        uint256 maxNonce = type(uint256).max;

        vm.prank(alice);
        vm.expectRevert();
        daoCollateral.invalidateUpToNonce(maxNonce + 1);
    }

    function testPartialMatchThenInvalidateNonceResetOrderAmount() public {
        (RwaMock rwaToken, Intent memory intent, Approval memory approval) = setupTest(TOTAL_AMOUNT);
        uint256[] memory orderAmounts = new uint256[](1);
        orderAmounts[0] = PARTIAL_AMOUNT;
        uint256[] memory orderIds = setupUsdcOrders(orderAmounts);

        uint256 initialNonce = daoCollateral.nonces(alice);

        vm.expectEmit(true, true, true, true);
        emit Swap(alice, address(rwaToken), PARTIAL_AMOUNT, PARTIAL_AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit IntentMatched(alice, initialNonce, address(rwaToken), PARTIAL_AMOUNT, PARTIAL_AMOUNT);

        vm.prank(alice);
        daoCollateral.swapRWAtoStbcIntent(orderIds, approval, intent, true);

        assertEq(
            daoCollateral.nonces(alice),
            initialNonce,
            "Nonce should not increment after partial match"
        );
        assertEq(
            daoCollateral.orderAmountTakenCurrentNonce(alice),
            PARTIAL_AMOUNT,
            "Incorrect amount taken"
        );
        // Snapshot current EVM state to call both nonce invalidation functions without bloating test cases
        uint256 currentStateId = vm.snapshot();
        vm.prank(alice);
        daoCollateral.invalidateUpToNonce(initialNonce + 1);
        assertEq(
            daoCollateral.orderAmountTakenCurrentNonce(alice), 0, "Order amount taken should reset"
        );

        vm.revertTo(currentStateId);
        assertGt(
            daoCollateral.orderAmountTakenCurrentNonce(alice),
            0,
            "Order amount taken should not be reset"
        );
        vm.prank(alice);
        daoCollateral.invalidateNonce();
        assertEq(
            daoCollateral.orderAmountTakenCurrentNonce(alice), 0, "Order amount taken should reset"
        );
    }

    /*//////////////////////////////////////////////////////////////
                14. REAL LIFE SCENARIOS WITH SWAPPER ENGINE
    //////////////////////////////////////////////////////////////*/

    function testSwapperEngineAndSwap(uint256 amount) public {
        amount = bound(amount, MINIMUM_USDC_PROVIDED + 1, type(uint128).max - 1);

        (RwaMock token, Usd0 stbc) = testRWASwap(amount);
        uint256 usd0WadAmount = amount * 1e12;

        // ** USD0 => USDC (swapperEngine)

        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 1;

        // Get the current USDC price in WAD format
        uint256 usdcWadPrice = _getUsdcWadPrice(); // price of 1e6 usdc in 1e18
        // calculate the amount of USDC for the given USD0 amount
        uint256 expectedUsdcAmount =
            _getUsdcAmountFromUsd0WadEquivalent(usd0WadAmount, usdcWadPrice);

        assertEq(usdcWadPrice, 1e18);
        // bob creates a USDC offer to be matched with alice USD0
        vm.startPrank(bob);
        deal(address(USDC), bob, expectedUsdcAmount);
        IUSDC(address(USDC)).approve(address(swapperEngine), expectedUsdcAmount);
        swapperEngine.depositUSDC(expectedUsdcAmount);
        vm.stopPrank();
        vm.startPrank(alice);
        IERC20(address(stbcToken)).approve(address(swapperEngine), usd0WadAmount);

        vm.expectEmit(true, true, true, true);
        emit OrderMatched(bob, alice, 1, expectedUsdcAmount);
        uint256 unmatched =
            swapperEngine.provideUsd0ReceiveUSDC(alice, expectedUsdcAmount, orderIdsToTake, false);
        vm.stopPrank();
        assertEq(unmatched, 0);
        assertEq(IUSDC(address(USDC)).balanceOf(alice), expectedUsdcAmount);
        assertEq(IERC20(address(stbcToken)).balanceOf(bob), usd0WadAmount);

        // ** USDC => USD0 (swapperEngine)
        // now alice will create an USDC offer to get USD0 back
        vm.startPrank(alice);
        IUSDC(address(USDC)).approve(address(swapperEngine), expectedUsdcAmount);
        swapperEngine.depositUSDC(expectedUsdcAmount);
        vm.stopPrank();
        // bob will match this offer with USD0
        orderIdsToTake[0] = 2;
        vm.startPrank(bob);
        IERC20(address(stbcToken)).approve(address(swapperEngine), usd0WadAmount);

        vm.expectEmit(true, true, true, true);
        emit OrderMatched(alice, bob, 2, expectedUsdcAmount);
        unmatched =
            swapperEngine.provideUsd0ReceiveUSDC(bob, expectedUsdcAmount, orderIdsToTake, false);
        vm.stopPrank();
        assertEq(unmatched, 0);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), expectedUsdcAmount);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), usd0WadAmount);
        // ** USD0 =>  RWA (daoCollateral)
        // alice redeems her USD0 for RWA

        uint256 amountInRWA = (usd0WadAmount) / 1e12;
        vm.prank(alice);
        daoCollateral.redeem(address(token), usd0WadAmount, 0);
        // The formula to calculate the amount of RWA that the user
        assertEq(stbc.balanceOf(alice), 0);
        uint256 fee = _getDotOnePercent(amountInRWA);
        uint256 rwaBalance = token.balanceOf(alice);
        assertEq(rwaBalance, amountInRWA - fee);
        assertLt(rwaBalance, amount);
    }

    function testSwapperEngineAndSwapWithPriceChangeFuzzing(uint256 rwaPrice) public {
        // uint256 rwaPrice = 1e4;
        rwaPrice = bound(rwaPrice, 1e4, 100e18);
        uint256 amount = 200_000e8;

        (RwaMock token, Usd0 stbc) = setupCreationRwa1_withMint(6, amount);
        vm.prank(alice);

        _setOraclePrice(address(token), rwaPrice);
        uint256 wadRwaPrice = rwaPrice * 1e12;

        // RWA => USD0
        // we have to take into account token price 1e6 * 1e18 / 1e6 == 1e18
        uint256 usd0WadAmount = amount * rwaPrice * 1e12 / 1e6;

        vm.prank(alice);
        daoCollateral.swap(address(token), amount, usd0WadAmount);
        // it is the same as price is 1e18 except for the imprecision
        assertEq(stbc.balanceOf(alice), usd0WadAmount);

        // ** USD0 => USDC (swapperEngine)

        uint256[] memory orderIdsToTake = new uint256[](1);
        orderIdsToTake[0] = 1;

        // Get the current USDC price in WAD format
        uint256 usdcWadPrice = _getUsdcWadPrice(); // price of 1e6 usdc in 1e18
        // calculate the amount of USDC for the given USD0 amount
        uint256 expectedUsdcAmount =
            _getUsdcAmountFromUsd0WadEquivalent(usd0WadAmount, usdcWadPrice);

        assertEq(usdcWadPrice, 1e18);
        // bob creates a USDC offer to be matched with alice USD0
        vm.startPrank(bob);
        deal(address(USDC), bob, expectedUsdcAmount);
        IUSDC(address(USDC)).approve(address(swapperEngine), expectedUsdcAmount);
        swapperEngine.depositUSDC(expectedUsdcAmount);
        vm.stopPrank();
        vm.startPrank(alice);
        IERC20(address(stbcToken)).approve(address(swapperEngine), usd0WadAmount);

        vm.expectEmit(true, true, true, true);
        emit OrderMatched(bob, alice, 1, expectedUsdcAmount);
        uint256 unmatched =
            swapperEngine.provideUsd0ReceiveUSDC(alice, expectedUsdcAmount, orderIdsToTake, false);
        vm.stopPrank();
        assertEq(unmatched, 0);
        assertEq(IUSDC(address(USDC)).balanceOf(alice), expectedUsdcAmount);
        assertEq(IERC20(address(stbcToken)).balanceOf(bob), usd0WadAmount);

        // ** USDC => USD0 (swapperEngine)
        // now alice will create an USDC offer to get USD0 back
        vm.startPrank(alice);
        IUSDC(address(USDC)).approve(address(swapperEngine), expectedUsdcAmount);
        swapperEngine.depositUSDC(expectedUsdcAmount);
        vm.stopPrank();
        // bob will match this offer with USD0
        orderIdsToTake[0] = 2;
        vm.startPrank(bob);
        IERC20(address(stbcToken)).approve(address(swapperEngine), usd0WadAmount);

        vm.expectEmit(true, true, true, true);
        emit OrderMatched(alice, bob, 2, expectedUsdcAmount);
        unmatched =
            swapperEngine.provideUsd0ReceiveUSDC(bob, expectedUsdcAmount, orderIdsToTake, false);
        vm.stopPrank();
        assertEq(unmatched, 0);
        assertEq(IUSDC(address(USDC)).balanceOf(bob), expectedUsdcAmount);
        assertEq(IERC20(address(stbcToken)).balanceOf(alice), usd0WadAmount);
        // ** USD0 =>  RWA (daoCollateral)
        // alice redeems her USD0 for RWA

        // uint256 amountInRWA = (usd0WadAmount) / 1e12;
        uint256 amountInRWA = (usd0WadAmount) * 1e6 / wadRwaPrice;
        vm.prank(alice);
        daoCollateral.redeem(address(token), usd0WadAmount, 0);
        // The formula to calculate the amount of RWA that the user
        assertEq(stbc.balanceOf(alice), 0);
        uint256 fee = _getDotOnePercent(amountInRWA);
        uint256 rwaBalance = token.balanceOf(alice);
        assertEq(rwaBalance, amountInRWA - fee);
        assertLt(rwaBalance, amount);
    }
}
