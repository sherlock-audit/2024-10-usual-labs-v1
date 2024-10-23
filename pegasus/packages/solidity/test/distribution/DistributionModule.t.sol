// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import "forge-std/console.sol";

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {Pausable} from "openzeppelin-contracts/utils/Pausable.sol";

import {SetupTest} from "../setup.t.sol";
import {UsualSPMock} from "src/mock/token/UsualSPMock.sol";
import {UsualXMock} from "src/mock/token/UsualXMock.sol";

import {DistributionModule} from "src/distribution/DistributionModule.sol";
import {IDistributionModule} from "src/interfaces/distribution/IDistributionModule.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";

import {BASIS_POINT_BASE} from "src/constants.sol";

import {
    SameValue,
    NullContract,
    NotAuthorized,
    PercentagesSumNotEqualTo100Percent,
    NullMerkleRoot,
    NoOffChainDistributionToApprove,
    NoTokensToClaim,
    InvalidProof,
    InvalidInput,
    CannotDistributeUsualMoreThanOnceADay
} from "src/errors.sol";

import {
    BPS_SCALAR,
    SCALAR_ONE,
    BASIS_POINT_BASE,
    RATE0,
    CONTRACT_TREASURY,
    USUAL_DISTRIBUTION_CHALLENGE_PERIOD,
    CONTRACT_USUALSP,
    CONTRACT_USUALX,
    LBT_DISTRIBUTION_SHARE,
    LYT_DISTRIBUTION_SHARE,
    IYT_DISTRIBUTION_SHARE,
    BRIBE_DISTRIBUTION_SHARE,
    ECO_DISTRIBUTION_SHARE,
    DAO_DISTRIBUTION_SHARE,
    MARKET_MAKERS_DISTRIBUTION_SHARE,
    USUALX_DISTRIBUTION_SHARE,
    USUALSTAR_DISTRIBUTION_SHARE,
    DISTRIBUTION_FREQUENCY_SCALAR
} from "src/constants.sol";

contract DistributionModuleTest is SetupTest {
    uint256 constant INITIAL_USD0PP_SUPPLY = 57_151.57026e18;
    uint256 constant INITIAL_RATE0 = 545;

    DailyData[] public realData;
    UsualSPMock usualSPMock;
    UsualXMock usualXMock;

    event OffChainDistributionQueued(uint256 indexed timestamp, bytes32 merkleRoot);
    event OffChainDistributionClaimed(address indexed account, uint256 amount);
    event ParameterUpdated(string parameterName, uint256 newValue);

    event UsualAllocatedForOffChainClaim(uint256 amount);
    event UsualAllocatedForUsualX(uint256 amount);
    event UsualAllocatedForUsualStar(uint256 amount);

    bytes32 constant FIRST_MERKLE_ROOT =
        bytes32(0xb27bba74a96ad64a5af960ef7109122a74d29e60b33b803a95a8169452bab97c);

    bytes32 constant SECOND_MERKLE_ROOT =
        bytes32(0x42c0f6fb540d80944343aa60ad559f96980e8217b5893243536bfe7acc6a9325);

    uint256 public aliceAmountInFirstMerkleTree = 10e18;
    uint256 public aliceAmountInSecondMerkleTree = 20e18;

    function _aliceProofForFirstMerkleTree() internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(0xd264c5e17b739c107b433ce4e73900487afb6cc6cbeb9f1651a640e411a591db);
        proof[1] = bytes32(0xdb61b8f77a945a119bb321e1044d8808ab64c81210661e930d0bf8363218d3ba);
        return proof;
    }

    function _aliceProofForSecondMerkleTree() internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(0xd704cf18239df2db7bb4fbdbf9a5ba2d210366214444bf3a1d11b8be63f5e62d);
        proof[1] = bytes32(0x7a01ed93feeb76b2608cfad220ccddf2470e723027d73ed4ee49208a6fbe91de);
        return proof;
    }

    struct DailyData {
        uint256 day;
        uint256 totalSupply;
        uint256 gamma;
        uint256 ratet;
        uint256 p90Rate;
        uint256 rate0;
        uint256 expectedUsualDist;
    }
    /*//////////////////////////////////////////////////////////////
                            1. SETUP & HELPERS
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();

        uint256 amount = INITIAL_USD0PP_SUPPLY;
        vm.prank(address(daoCollateral));
        deal(address(stbcToken), alice, amount);

        vm.startPrank(address(alice));
        stbcToken.approve(address(usd0PP), amount);
        usd0PP.mint(amount);
        vm.stopPrank();
        // After minting, we need to reinitialize the DistributionModule
        // This is because the initial supply is stored during initialization
        _resetInitializerImplementation(address(distributionModule));
        vm.prank(admin);
        distributionModule.initialize(registryContract, INITIAL_RATE0);

        usualSPMock = new UsualSPMock(usualToken);
        usualXMock = new UsualXMock();
    }

    function setUpTestData() internal {
        realData.push(DailyData(1, 57_151.57026e18, 10_000, 545, 551, 545, 391.4491e18));
        realData.push(DailyData(2, 38_360_239.9e18, 10_000, 546, 551, 546, 392.1674e18));
        realData.push(DailyData(3, 47_942_400.76e18, 10_000, 548, 551, 547, 393.6039e18));
        realData.push(DailyData(4, 54_385_577.55e18, 10_000, 547, 5501, 547, 392.8856e18));
        realData.push(DailyData(5, 59_627_462.99e18, 10_000, 547, 5501, 547, 392.8856e18));
        realData.push(DailyData(6, 60_849_671.14e18, 10_000, 547, 5501, 547, 392.8856e18));
        realData.push(DailyData(7, 68_263_281.09e18, 10_000, 548, 5501, 548, 393.6039e18));
        realData.push(DailyData(8, 69_908_471.89e18, 10_000, 548, 550, 548, 393.6039e18));
        realData.push(DailyData(9, 72_451_402.37e18, 10_000, 547, 550, 548, 392.8856e18));
        realData.push(DailyData(10, 73_385_798.95e18, 10_000, 548, 550, 548, 393.6039e18));
        realData.push(DailyData(11, 75_588_247.22e18, 10_000, 548, 550, 548, 393.6039e18));
    }

    function getExpectedTotalUsualDistributionForTestData() internal view returns (uint256) {
        uint256 totalUsualDist = 0;
        for (uint256 i = 1; i < realData.length; i++) {
            totalUsualDist += realData[i].expectedUsualDist;
        }
        return totalUsualDist;
    }

    modifier calledByDistributionAllocator() {
        vm.startPrank(distributionAllocator);
        _;
        vm.stopPrank();
    }

    modifier calledByPausingRole() {
        vm.startPrank(pauser);
        _;
        vm.stopPrank();
    }

    modifier calledByDefaultAdminRole() {
        vm.startPrank(admin);
        _;
        vm.stopPrank();
    }

    modifier calledByDistributionOperatorRole() {
        vm.startPrank(distributionOperator);
        _;
        vm.stopPrank();
    }

    modifier calledByDistributionChallengerRole() {
        vm.startPrank(distributionChallenger);
        _;
        vm.stopPrank();
    }

    modifier modulePaused() {
        vm.prank(pauser);
        distributionModule.pause();

        _;
    }

    modifier distributionsQueuedFor(uint256 numberOfDays) {
        vm.startPrank(distributionOperator);
        for (uint256 i = 0; i < numberOfDays; i++) {
            skip(DISTRIBUTION_FREQUENCY_SCALAR);
            distributionModule.queueOffChainUsualDistribution(FIRST_MERKLE_ROOT);
        }
        vm.stopPrank();
        _;
    }

    modifier challengedDistributionQueued(uint256 numberOfDays) {
        uint256 timestampToChallengeFrom = block.timestamp;

        vm.startPrank(distributionOperator);
        for (uint256 i = 0; i < numberOfDays; i++) {
            skip(DISTRIBUTION_FREQUENCY_SCALAR);
            distributionModule.queueOffChainUsualDistribution(FIRST_MERKLE_ROOT);
        }
        vm.stopPrank();

        vm.prank(distributionChallenger);
        distributionModule.challengeOffChainDistribution(timestampToChallengeFrom);
        _;
    }

    modifier queueAndApproveDistribution(bytes32 merkleRoot) {
        vm.startPrank(distributionOperator);
        distributionModule.queueOffChainUsualDistribution(merkleRoot);
        skip(USUAL_DISTRIBUTION_CHALLENGE_PERIOD + 1);

        distributionModule.approveUnchallengedOffChainDistribution();
        vm.stopPrank();
        _;
    }

    modifier setBucketDistributionToOnlyOffChainBuckets() {
        vm.prank(distributionAllocator);
        distributionModule.setBucketsDistribution(BASIS_POINT_BASE, 0, 0, 0, 0, 0, 0, 0, 0);
        _;
    }

    modifier setBucketsDistribution(uint256 offChain, uint256 usualStar, uint256 usualX) {
        vm.prank(distributionAllocator);
        distributionModule.setBucketsDistribution(offChain, 0, 0, 0, 0, 0, 0, usualStar, usualX);
        _;
    }

    modifier useUsualStarMock() {
        vm.prank(admin);
        registryContract.setContract(CONTRACT_USUALSP, address(usualSPMock));
        _resetInitializerImplementation(address(distributionModule));
        distributionModule.initialize(registryContract, INITIAL_RATE0);

        _;
    }

    modifier useUsualXMock() {
        vm.prank(admin);
        registryContract.setContract(CONTRACT_USUALX, address(usualXMock));
        _resetInitializerImplementation(address(distributionModule));
        distributionModule.initialize(registryContract, INITIAL_RATE0);
        _;
    }

    modifier distributeUsualForTestData() {
        setUpTestData();

        vm.prank(distributionAllocator);
        distributionModule.setBucketsDistribution(BASIS_POINT_BASE, 0, 0, 0, 0, 0, 0, 0, 0);

        for (uint256 i = 1; i < realData.length; i++) {
            DailyData memory data = realData[i];
            skip(DISTRIBUTION_FREQUENCY_SCALAR);
            vm.prank(distributionOperator);
            distributionModule.distributeUsualToBuckets(data.ratet, data.p90Rate);
        }
        _;
    }

    modifier distributeUsualOnlyToAllBucketsForTestData() {
        setUpTestData();

        for (uint256 i = 1; i < realData.length; i++) {
            DailyData memory data = realData[i];
            skip(DISTRIBUTION_FREQUENCY_SCALAR);
            vm.prank(distributionOperator);
            distributionModule.distributeUsualToBuckets(data.ratet, data.p90Rate);
        }
        _;
    }

    modifier aliceClaimedFromApprovedFirstMerkleTree() {
        distributionModule.claimOffChainDistribution(
            alice, aliceAmountInFirstMerkleTree, _aliceProofForFirstMerkleTree()
        );
        _;
    }

    /// @notice Sanity check for isCBROn function
    /// @dev Verifies the initial state of CBR (Collateral Backing Ratio) and its effect on USD0PP price
    function test_IsCBROn() public view {
        bool isCBROn = daoCollateral.isCBROn();
        assertEq(isCBROn, false);
    }

    /*//////////////////////////////////////////////////////////////
                            2. INITIALIZER
    //////////////////////////////////////////////////////////////*/

    // 2.1 Testing revert properties //
    function test_Initializer_Should_FailWhenRegistryAddressIsNullContract() external {
        _resetInitializerImplementation(address(distributionModule));
        vm.expectRevert(abi.encodeWithSelector(NullContract.selector));
        distributionModule.initialize(IRegistryContract(address(0)), RATE0);
    }

    function test_Initializer_Should_RevertWhenRate0IsZero() external {
        _resetInitializerImplementation(address(distributionModule));
        vm.expectRevert(abi.encodeWithSelector(InvalidInput.selector));
        distributionModule.initialize(registryContract, 0);
    }

    function test_GetOffChainDistributionData_Should_BeEmptyAfterInitialization() external view {
        (uint256 timestamp, bytes32 merkleRoot) = distributionModule.getOffChainDistributionData();
        assertEq(timestamp, 0);
        assertEq(merkleRoot, bytes32(0));
    }

    function test_GetOffChainTokensClaimed_Should_ReturnZeroForAnyAddressAfterInitialization(
        address claimer
    ) external view {
        assertEq(distributionModule.getOffChainTokensClaimed(claimer), 0);
    }

    // 2.2 Testing successful initialization //

    function testAnyoneCanCreateDistributionModule() external {
        DistributionModule distributionModule = new DistributionModule();
        _resetInitializerImplementation(address(distributionModule));
        distributionModule.initialize(registryContract, RATE0);
        assertTrue(address(distributionModule) != address(0));
    }

    function test_Initializer_Should_Work() external {
        _resetInitializerImplementation(address(distributionModule));
        vm.prank(admin);
        distributionModule.initialize(registryContract, RATE0);

        (
            uint256 lbt,
            uint256 lyt,
            uint256 iyt,
            uint256 bribe,
            uint256 eco,
            uint256 dao,
            uint256 marketMakers,
            uint256 usualP,
            uint256 usualStar
        ) = distributionModule.getBucketsDistribution();

        assertEq(lbt, LBT_DISTRIBUTION_SHARE);
        assertEq(lyt, LYT_DISTRIBUTION_SHARE);
        assertEq(iyt, IYT_DISTRIBUTION_SHARE);
        assertEq(bribe, BRIBE_DISTRIBUTION_SHARE);
        assertEq(eco, ECO_DISTRIBUTION_SHARE);
        assertEq(dao, DAO_DISTRIBUTION_SHARE);
        assertEq(marketMakers, MARKET_MAKERS_DISTRIBUTION_SHARE);
        assertEq(usualP, USUALX_DISTRIBUTION_SHARE);
        assertEq(usualStar, USUALSTAR_DISTRIBUTION_SHARE);
    }

    /*//////////////////////////////////////////////////////////////
                            3. DISTRIBUTION MODULE
    //////////////////////////////////////////////////////////////*/

    // 3.1 Testing getBucketsDistribution //
    function test_GetBucketsDistribution() external view {
        (
            uint256 lbt,
            uint256 lyt,
            uint256 iyt,
            uint256 bribe,
            uint256 eco,
            uint256 dao,
            uint256 marketMakers,
            uint256 usualP,
            uint256 usualStar
        ) = distributionModule.getBucketsDistribution();

        assertEq(lbt, 4044);
        assertEq(lyt, 2256);
        assertEq(iyt, 400);
        assertEq(bribe, 400);
        assertEq(eco, 250);
        assertEq(dao, 300);
        assertEq(marketMakers, 350);
        assertEq(usualP, 1000);
        assertEq(usualStar, 1000);
    }

    // 3.2 Testing calculateSt //

    function test_Usd0ppTotalSupply() public view {
        uint256 totalSupply = usd0PP.totalSupply();

        // Assuming a reasonable range for total supply
        // Adjust these bounds based on your expected initial supply
        uint256 minExpectedSupply = 50_000e18; // 1 million USD0PP
        uint256 maxExpectedSupply = 1_000_000_000e18; // 1 billion USD0PP

        assertGe(totalSupply, minExpectedSupply, "USD0PP total supply is lower than expected");
        assertLe(totalSupply, maxExpectedSupply, "USD0PP total supply is higher than expected");
    }
    // @notice Fuzz test for calculateSt function
    /// @dev Tests that calculateSt doesn't overflow and returns expected results within bounds
    /// @param supplyPpt Random supply value
    /// @param pt Random price value

    function testFuzz_CalculateSt(uint256 supplyPpt, uint256 pt) public view {
        supplyPpt = bound(supplyPpt, 1e18, 10_000_000_000_000e18); // 1 to 10 trillion
        pt = bound(pt, 0.1e18, 10_000_000_000e18); // 0.1 to 10 billion

        uint256 result = distributionModule.calculateSt(supplyPpt, pt);

        // Check result is within expected bounds (0, 1e18]
        assertLe(result, 1e18);
        assertGe(result, 0);
    }

    /// @notice Fuzz test for calculateRt function
    /// @dev Tests that calculateRt doesn't overflow and returns expected results within bounds
    /// @param ratet Random current rate
    /// @param p90Rate Random 90-day rate
    function testFuzz_CalculateRt(uint256 ratet, uint256 p90Rate) public view {
        ratet = bound(ratet, 1, 5000); // 0.01% to 50%
        p90Rate = bound(p90Rate, 10, 5000); // 0.01% to 50%

        uint256 result = distributionModule.calculateRt(ratet, p90Rate);

        // Check result is within expected bounds (0, ~10e18]
        assertLe(result, 10e18); // Allow some margin for rate increases
        assertGt(result, 0);
    }

    /// @notice Fuzz test for calculateRt function
    /// @dev Tests that calculateRt doesn't overflow and returns expected results within bounds
    /// @param ratet Random current rate
    /// @param p90Rate Random 90-day rate
    function testFuzz_CalculateRtRealistic(uint256 ratet, uint256 p90Rate) public view {
        ratet = bound(ratet, 1, 1000); // 0.001% to 10%
        p90Rate = bound(p90Rate, 10, 1000); // 0.01% to 10%

        uint256 result = distributionModule.calculateRt(ratet, p90Rate);

        // Check result is within expected bounds (0, ~1e18]
        assertLe(result, 1.89e18); // Allow some margin for rate increases (=0.1/0.0546) based on our assumed rate0 and rates at time t of 10%
        assertGt(result, 0);
    }

    /// @notice Fuzz test for calculateKappa function
    /// @dev Tests that calculateKappa doesn't overflow and returns expected results within bounds
    /// @param rt Random Rt values
    function testFuzz_CalculateKappaRealistic(uint256 rt) public view {
        rt = bound(rt, 1, 1000); // 0.001% to 10%

        uint256 result = distributionModule.calculateKappa(rt);

        // Check result is within expected bounds [0, 20]
        assertLe(result, 19e18);
        assertGe(result, 0);
    }

    /// @notice Fuzz test for calculateKappa function
    /// @dev Tests that calculateKappa doesn't overflow and returns expected results within bounds
    /// @param rt Random Rt values
    function testFuzz_CalculateKappa(uint256 rt) public view {
        rt = bound(rt, 1, 5000); // 0.001% to 50%

        uint256 result = distributionModule.calculateKappa(rt);

        // Check result is within expected bounds [0, 92]
        assertLe(result, 92e18);
        assertGe(result, 0);
    }

    function testInitialGammaCalculation() public view {
        uint256 expectedGamma = SCALAR_ONE;
        uint256 calculatedGamma = distributionModule.calculateGamma();

        assertEq(
            calculatedGamma, expectedGamma, "Initial gamma calculation should return base gamma"
        );
    }

    /// @notice Fuzz test for calculateMt function
    /// @dev Tests that calculateMt doesn't overflow and returns expected results within bounds
    /// @param st Random St value
    /// @param rt Random Rt value
    /// @param kappa Random Kappa value
    function testFuzz_CalculateMt(uint256 st, uint256 rt, uint256 kappa) public view {
        st = bound(st, 0, 1e18); // 0 to 1
        rt = bound(rt, 0, 2e18); // 0 to 2
        kappa = bound(kappa, 0e18, 20e18); // 1 to 100

        uint256 result = distributionModule.calculateMt(st, rt, kappa);

        // Check result is within expected bounds [0, kappa]
        assertLe(result, kappa);
        assertGe(result, 0);
    }

    /// Fuzz gamma between 0.5 and 2 , we expect mt to be between rt 0-2 rt 0-1 then Mt should be between 0 and 40
    /// @notice Fuzz test for calculateUsualDist function
    /// @dev Tests that calculateUsualDist doesn't overflow and returns expected results
    /// @param ratet Random current rate
    /// @param p90Rate Random 90-day rate
    function testFuzz_CalculateUsualDist(uint256 ratet, uint256 p90Rate) public view {
        ratet = bound(ratet, 1, 1000); // 0.01% to 10%
        p90Rate = bound(p90Rate, 10, 1000); // 0.01% to 10%

        (uint256 st, uint256 rt, uint256 kappa, uint256 mt,) =
            distributionModule.calculateUsualDist(ratet, p90Rate);

        // Check intermediate results
        assertLe(st, 1e18);

        assertLe(rt, 2e18);

        assertLe(mt, kappa);
    }

    /// @notice Test for potential overflow in economic calculations
    /// @dev Uses max possible values to check for overflows in all calculation functions
    function test_OverflowProtection() public view {
        uint256 maxUint = type(uint256).max;

        // Test calculateMt with max values
        uint256 mt = distributionModule.calculateMt(1e18, 2e18, maxUint);
        assertLe(mt, maxUint);

        // Test calculateUsualDist with max values
        (,,,, uint256 usualDist) = distributionModule.calculateUsualDist(10_000, 10_000);
        assertLe(usualDist, 10_000e18);
    }

    // 3.4 Simulations with real realData
    function simulateDay(DailyData memory data) internal {
        uint256 currentSupply = usd0PP.totalSupply();

        if (data.totalSupply > currentSupply) {
            // Mint additional tokens if supply increased
            uint256 supplyToMint = data.totalSupply - currentSupply;
            vm.prank(address(daoCollateral));
            deal(address(stbcToken), alice, supplyToMint);
            vm.startPrank(address(alice));
            stbcToken.approve(address(usd0PP), supplyToMint);
            usd0PP.mint(supplyToMint);
            vm.stopPrank();
        } else if (data.totalSupply < currentSupply) {
            // Burn tokens if supply decreased
            assertEq(data.totalSupply, currentSupply, "Total supply decreased unexpectedly");
        }

        // Calculate and check the usual distribution
        (uint256 st, uint256 rt, uint256 kappa, uint256 mt, uint256 usualDist) =
            distributionModule.calculateUsualDist(data.ratet, data.p90Rate);

        console.log("Day:", data.day);
        console.log("TotalSupply:", usd0PP.totalSupply());
        console.log("St:", st);
        console.log("Rt:", rt);
        console.log("Kappa:", kappa);
        console.log("Mt:", mt);
        console.log("UsualDist:", usualDist);
        console.log("Expected UsualDist:", data.expectedUsualDist);
        console.log("------------------------");

        assertApproxEqRel(usualDist, data.expectedUsualDist, 1e15); // Allow 0.1% deviation
    }

    function testDistributionWithCBRActivatedExtreme() public {
        // Setup initial state
        setUpTestData();
        uint256 initialSupply = realData[1].totalSupply - usd0PP.totalSupply();

        // Mint initial supply
        vm.prank(address(daoCollateral));
        deal(address(stbcToken), alice, initialSupply);
        vm.startPrank(alice);
        stbcToken.approve(address(usd0PP), initialSupply);
        usd0PP.mint(initialSupply);
        vm.stopPrank();

        // Check initial state
        assertEq(usd0PP.totalSupply(), realData[1].totalSupply);
        assertEq(daoCollateral.isCBROn(), false);

        // Calculate initial distribution
        (
            uint256 initialSt,
            uint256 initialRt,
            uint256 initialKappa,
            uint256 initialMt,
            uint256 initialUsualDist
        ) = distributionModule.calculateUsualDist(realData[1].ratet, realData[1].p90Rate);

        console.log("Initial St:", initialSt);
        console.log("Initial Rt:", initialRt);
        console.log("Initial Kappa:", initialKappa);
        console.log("Initial Mt:", initialMt);
        console.log("Initial UsualDist:", initialUsualDist);

        // Simulate a price drop that would trigger CBR
        _setOraclePrice(address(stbcToken), 25e4);

        // Activate CBR
        vm.prank(admin);
        daoCollateral.setRedeemFee(0);
        vm.prank(admin);
        daoCollateral.activateCBR(0.001e18); // Set CBR coefficient to 0.001 should cap out st at 1
        vm.prank(distributionAllocator);
        distributionModule.setBaseGamma(9999); // Set gamma below 1 should clamp supply factor to kappa

        // Check CBR state
        assertEq(daoCollateral.isCBROn(), true);
        assertEq(daoCollateral.cbrCoef(), 0.001e18);

        // Calculate distribution with CBR active
        (uint256 st, uint256 rt, uint256 kappa, uint256 mt, uint256 usualDist) =
            distributionModule.calculateUsualDist(realData[1].ratet, realData[1].p90Rate);

        // Log results
        console.log("St:", st);
        console.log("Rt:", rt);
        console.log("Kappa:", kappa);
        console.log("Mt:", mt);
        console.log("UsualDist with CBR:", usualDist);

        assertApproxEqAbs(st, 1e18, 0, "st should cap out at 1 CBR is activated");
        assertApproxEqAbs(kappa, mt, 30e18, "supply factor should clamp to around Kappa"); //note: kappa is a fail safe
        assertApproxEqAbs(initialRt, rt, 0, "rt should stay the same when CBR is activated");
        // Check that usual distribution stays the same
        // NOTE: this will not always be the case when we move into multi collateral environment
        assertLe(usualDist, initialUsualDist);
        uint256 expectedUsualDist = 263_249_788_412_296_048_961;
        assertApproxEqAbs(usualDist, expectedUsualDist, 0, "usual distribution");
    }

    function testDistributionWithCBRActivated() public {
        // Setup initial state
        setUpTestData();
        uint256 initialSupply = realData[1].totalSupply - usd0PP.totalSupply();

        // Mint initial supply
        vm.prank(address(daoCollateral));
        deal(address(stbcToken), alice, initialSupply);
        vm.startPrank(alice);
        stbcToken.approve(address(usd0PP), initialSupply);
        usd0PP.mint(initialSupply);
        vm.stopPrank();

        // Check initial state
        assertEq(usd0PP.totalSupply(), realData[1].totalSupply);
        assertEq(daoCollateral.isCBROn(), false);

        // Calculate initial distribution
        (
            uint256 initialSt,
            uint256 initialRt,
            uint256 initialKappa,
            uint256 initialMt,
            uint256 initialUsualDist
        ) = distributionModule.calculateUsualDist(realData[1].ratet, realData[1].p90Rate);

        console.log("Initial St:", initialSt);
        console.log("Initial Rt:", initialRt);
        console.log("Initial Kappa:", initialKappa);
        console.log("Initial Mt:", initialMt);
        console.log("Initial UsualDist:", initialUsualDist);

        // Simulate a price drop that would trigger CBR
        _setOraclePrice(address(stbcToken), 25e4);

        // Activate CBR
        vm.prank(admin);
        daoCollateral.setRedeemFee(0);
        vm.prank(admin);
        daoCollateral.activateCBR(0.5e18); // Set CBR coefficient to 0.5

        // Check CBR state
        assertEq(daoCollateral.isCBROn(), true);
        assertEq(daoCollateral.cbrCoef(), 0.5e18);

        // Calculate distribution with CBR active
        (uint256 st, uint256 rt, uint256 kappa, uint256 mt, uint256 usualDist) =
            distributionModule.calculateUsualDist(realData[1].ratet, realData[1].p90Rate);

        // Log results
        console.log("St:", st);
        console.log("Rt:", rt);
        console.log("Kappa:", kappa);
        console.log("Mt:", mt);
        console.log("UsualDist with CBR:", usualDist);

        assertApproxEqAbs(initialMt * 2, mt, 1, "supply factor should double when CBR is activated");
        assertApproxEqAbs(
            initialSt * 2, st, 0, "st should increase proportionately when CBR is activated"
        );
        assertApproxEqAbs(initialRt, rt, 0, "rt should stay the same when CBR is activated");
        // Check that usual distribution stays the same
        // NOTE: this will not always be the case when we move into multi collateral environment
        assertApproxEqAbs(
            initialUsualDist,
            usualDist,
            1e5,
            "usual distribution should stay the same when CBR is activated"
        );
    }

    function test_Simulation() public {
        setUpTestData();
        for (uint256 i = 1; i < realData.length; i++) {
            simulateDay(realData[i]);
        }
    }

    // 3.5 getOffChainDistributionMintCap
    function test_GetOffChainDistributionMintCap_Should_BeZeroAfterInitialization() external view {
        uint256 mintCap = distributionModule.getOffChainDistributionMintCap();
        assertEq(mintCap, 0);
    }

    function test_GetOffChainDistributionMintCap_Should_ReturnCorrectValue()
        external
        distributeUsualForTestData
    {
        uint256 mintCap = distributionModule.getOffChainDistributionMintCap();

        uint256 expectedUsualDist = getExpectedTotalUsualDistributionForTestData();

        assertApproxEqRel(mintCap, expectedUsualDist, 1e15);
    }

    // 3.6 getLastOnChainDistributionTimestamp
    function test_GetLastOnChainDistributionTimestamp_Should_BeZeroAfterInitialization()
        external
        view
    {
        uint256 timestamp = distributionModule.getLastOnChainDistributionTimestamp();
        assertEq(timestamp, 0);
    }

    function test_GetLastOnChainDistributionTimestamp_Should_ReturnCorrectValue()
        external
        distributeUsualForTestData
    {
        uint256 timestamp = distributionModule.getLastOnChainDistributionTimestamp();
        assertEq(timestamp, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                          4. DISTRIBUTION ALLOCATOR
    //////////////////////////////////////////////////////////////*/

    // 4.1 Testing setBucketsDistribution //
    function test_SetBucketsDistribution_Should_SetNewDistribution()
        external
        calledByDistributionAllocator
    {
        // NOTE: Merged into single value to avoid stack too deep error
        uint256 expectedLbtLytIyt = 3000;
        // NOTE: Merged into single value to avoid stack too deep error
        uint256 expectedBribeEcoDao = 300;
        uint256 expectedMarketMakers = 30;
        uint256 expectedUsualP = 30;
        uint256 expectedUsualStar = 40;

        distributionModule.setBucketsDistribution(
            expectedLbtLytIyt,
            expectedLbtLytIyt,
            expectedLbtLytIyt,
            expectedBribeEcoDao,
            expectedBribeEcoDao,
            expectedBribeEcoDao,
            expectedMarketMakers,
            expectedUsualP,
            expectedUsualStar
        );
        (
            uint256 lbt,
            uint256 lyt,
            uint256 iyt,
            uint256 bribe,
            uint256 eco,
            uint256 dao,
            uint256 marketMakers,
            uint256 usualP,
            uint256 usualStar
        ) = distributionModule.getBucketsDistribution();

        assertEq(lbt, expectedLbtLytIyt);
        assertEq(lyt, expectedLbtLytIyt);
        assertEq(iyt, expectedLbtLytIyt);
        assertEq(bribe, expectedBribeEcoDao);
        assertEq(eco, expectedBribeEcoDao);
        assertEq(dao, expectedBribeEcoDao);
        assertEq(marketMakers, expectedMarketMakers);
        assertEq(usualP, expectedUsualP);
        assertEq(usualStar, expectedUsualStar);
    }

    function test_SetBucketDistribution_Should_RevertWhenNotCalledByDistributionAllocator()
        external
    {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        distributionModule.setBucketsDistribution(0, 0, 0, 0, 0, 0, 0, 0, 0);
    }

    function test_SetBucketDistribution_Should_RevertWhenAllocationSumIsNotEqualTo100Percent()
        external
        calledByDistributionAllocator
    {
        vm.expectRevert(abi.encodeWithSelector(PercentagesSumNotEqualTo100Percent.selector));
        distributionModule.setBucketsDistribution(0, 0, 0, 0, 0, 0, 0, 0, 0);
    }

    function test_SetBucketDistribution_Should_EmitEventForAllParameters()
        external
        calledByDistributionAllocator
    {
        uint256 expectedLbt = 3000;
        uint256 expectedLyt = 3000;
        uint256 expectedIyt = 3000;
        uint256 expectedBribe = 300;
        uint256 expectedEco = 300;
        uint256 expectedDao = 300;
        uint256 expectedMarketMakers = 30;
        uint256 expectedUsualP = 30;
        uint256 expectedUsualStar = 40;

        vm.expectEmit(address(distributionModule));
        emit ParameterUpdated("lbt", expectedLbt);
        vm.expectEmit(address(distributionModule));
        emit ParameterUpdated("lyt", expectedLyt);
        vm.expectEmit(address(distributionModule));
        emit ParameterUpdated("iyt", expectedIyt);
        vm.expectEmit(address(distributionModule));
        emit ParameterUpdated("bribe", expectedBribe);
        vm.expectEmit(address(distributionModule));
        emit ParameterUpdated("eco", expectedEco);
        vm.expectEmit(address(distributionModule));
        emit ParameterUpdated("dao", expectedDao);
        vm.expectEmit(address(distributionModule));
        emit ParameterUpdated("marketMakers", expectedMarketMakers);
        vm.expectEmit(address(distributionModule));
        emit ParameterUpdated("usualX", expectedUsualP);
        vm.expectEmit(address(distributionModule));
        emit ParameterUpdated("usualStar", expectedUsualStar);

        distributionModule.setBucketsDistribution(
            expectedLbt,
            expectedLyt,
            expectedIyt,
            expectedBribe,
            expectedEco,
            expectedDao,
            expectedMarketMakers,
            expectedUsualP,
            expectedUsualStar
        );
    }

    // 4.2 Testing setD //
    function test_SetD_Should_RevertWhenNotCalledByDistributionAllocator() external {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        distributionModule.setD(0);
    }

    function test_SetD_Should_RevertWhenInputIsZero() external calledByDistributionAllocator {
        vm.expectRevert(abi.encodeWithSelector(InvalidInput.selector));
        distributionModule.setD(0);
    }

    function test_SetD_Should_Work() external calledByDistributionAllocator {
        uint256 expectedD = 0.1e18;
        distributionModule.setD(expectedD);
        assertEq(distributionModule.getD(), expectedD);
    }

    function test_SetD_Should_EmitEvent() external calledByDistributionAllocator {
        uint256 expectedD = 0.1e18;
        vm.expectEmit(address(distributionModule));
        emit ParameterUpdated("d", expectedD);
        distributionModule.setD(expectedD);
    }

    function test_SetD_Should_RevertWhenSettingToSameValue()
        external
        calledByDistributionAllocator
    {
        uint256 currentD = distributionModule.getD();
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        distributionModule.setD(currentD);
    }

    // 4.3 Testing setM0 //
    function test_SetM0_Should_RevertWhenNotCalledByDistributionAllocator() external {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        distributionModule.setM0(0);
    }

    function test_SetM0_Should_RevertWhenInputIsZero() external calledByDistributionAllocator {
        vm.expectRevert(abi.encodeWithSelector(InvalidInput.selector));
        distributionModule.setM0(0);
    }

    function test_SetM0_Should_Work() external calledByDistributionAllocator {
        uint256 expectedM0 = 0.1e18;
        distributionModule.setM0(expectedM0);
        assertEq(distributionModule.getM0(), expectedM0);
    }

    function test_SetM0_Should_EmitEvent() external calledByDistributionAllocator {
        uint256 expectedM0 = 0.1e18;
        vm.expectEmit(address(distributionModule));
        emit ParameterUpdated("m0", expectedM0);
        distributionModule.setM0(expectedM0);
    }

    function test_SetM0_Should_RevertWhenSettingToSameValue()
        external
        calledByDistributionAllocator
    {
        uint256 currentM0 = distributionModule.getM0();
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        distributionModule.setM0(currentM0);
    }

    // 4.4 Testing setRateMin //
    function test_SetRateMin_Should_RevertWhenNotCalledByDistributionAllocator() external {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        distributionModule.setRateMin(0);
    }

    function test_SetRateMin_Should_RevertWhenInputIsZero()
        external
        calledByDistributionAllocator
    {
        vm.expectRevert(abi.encodeWithSelector(InvalidInput.selector));
        distributionModule.setRateMin(0);
    }

    function test_SetRateMin_Should_Work() external calledByDistributionAllocator {
        uint256 expectedRateMin = 0.1e18;
        distributionModule.setRateMin(expectedRateMin);
        assertEq(distributionModule.getRateMin(), expectedRateMin);
    }

    function test_SetRateMin_Should_EmitEvent() external calledByDistributionAllocator {
        uint256 expectedRateMin = 0.1e18;
        vm.expectEmit(address(distributionModule));
        emit ParameterUpdated("rateMin", expectedRateMin);
        distributionModule.setRateMin(expectedRateMin);
    }

    function test_SetRateMin_Should_RevertWhenSettingToSameValue()
        external
        calledByDistributionAllocator
    {
        uint256 currentRateMin = distributionModule.getRateMin();
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        distributionModule.setRateMin(currentRateMin);
    }

    // 4.5 Testing setBaseGamma //

    function test_SetGamma_Should_RevertWhenNotCalledByDistributionAllocator() external {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        distributionModule.setBaseGamma(0);
    }

    function test_SetGamma_Should_RevertWhenInputIsZero() external calledByDistributionAllocator {
        vm.expectRevert(abi.encodeWithSelector(InvalidInput.selector));
        distributionModule.setBaseGamma(0);
    }

    function test_SetGamma_Should_Work() external calledByDistributionAllocator {
        uint256 expectedGamma = 0.1e18;
        distributionModule.setBaseGamma(expectedGamma);
        assertEq(distributionModule.getBaseGamma(), expectedGamma);
    }

    function test_SetGamma_Should_EmitEvent() external calledByDistributionAllocator {
        uint256 expectedGamma = 0.1e18;
        vm.expectEmit(address(distributionModule));
        emit ParameterUpdated("baseGamma", expectedGamma);
        distributionModule.setBaseGamma(expectedGamma);
    }

    function test_SetGamma_Should_RevertWhenSettingToSameValue()
        external
        calledByDistributionAllocator
    {
        uint256 currentGamma = distributionModule.getBaseGamma();
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        distributionModule.setBaseGamma(currentGamma);
    }

    /*//////////////////////////////////////////////////////////////
                          5. DISTRIBUTION OPERATOR
    //////////////////////////////////////////////////////////////*/
    // 5.1 Testing distributeUsualToBuckets //
    function test_DistributeUsualToBuckets_Should_RevertWhenNotCalledByDistributionOperator()
        external
    {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        distributionModule.distributeUsualToBuckets(0, 0);
    }

    function test_DistributeUsualToBuckets_Should_RevertWhenPaused()
        external
        modulePaused
        calledByDistributionOperatorRole
    {
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        distributionModule.distributeUsualToBuckets(0, 0);
    }

    function test_DistributeToUsualBuckets_Should_Revert_WhenCalledInLessThan24hours()
        external
        setBucketDistributionToOnlyOffChainBuckets
        calledByDistributionOperatorRole
    {
        setUpTestData();
        DailyData memory firstDayData = realData[0];
        DailyData memory secondDayData = realData[1];

        skip(DISTRIBUTION_FREQUENCY_SCALAR);
        distributionModule.distributeUsualToBuckets(firstDayData.ratet, firstDayData.p90Rate);

        skip(DISTRIBUTION_FREQUENCY_SCALAR - 1);
        vm.expectRevert(abi.encodeWithSelector(CannotDistributeUsualMoreThanOnceADay.selector));
        distributionModule.distributeUsualToBuckets(secondDayData.ratet, secondDayData.p90Rate);
    }

    function test_DistributeUsualToBuckets_Should_NotIncreaseMintCapWhenThereIsNoDistributionToOffChainBuckets(
    )
        external
        useUsualStarMock
        useUsualXMock
        setBucketsDistribution(0, 0, BASIS_POINT_BASE)
        calledByDistributionOperatorRole
    {
        setUpTestData();
        uint256 expectedMintCap = 0;

        skip(DISTRIBUTION_FREQUENCY_SCALAR);
        distributionModule.distributeUsualToBuckets(realData[0].ratet, realData[0].p90Rate);

        assertEq(distributionModule.getOffChainDistributionMintCap(), expectedMintCap);
    }

    function test_DistributeUsualToBuckets_Should_MintTokensToUsualStar()
        external
        useUsualStarMock
        useUsualXMock
        setBucketsDistribution(0, 0, BASIS_POINT_BASE)
        calledByDistributionOperatorRole
    {
        setUpTestData();

        uint256 usualStarBalanceBefore = usualToken.balanceOf(address(usualSPMock));

        skip(DISTRIBUTION_FREQUENCY_SCALAR);
        distributionModule.distributeUsualToBuckets(realData[0].ratet, realData[0].p90Rate);

        uint256 usualStarBalanceAfter = usualToken.balanceOf(address(usualSPMock));

        assertApproxEqRel(
            usualStarBalanceAfter - usualStarBalanceBefore, realData[0].expectedUsualDist, 1e15
        );
    }

    function test_DistributeUsualToBuckets_Should_StartDistributionInUsualStar()
        external
        useUsualStarMock
        setBucketsDistribution(0, 0, BASIS_POINT_BASE)
        calledByDistributionOperatorRole
    {
        setUpTestData();
        skip(DISTRIBUTION_FREQUENCY_SCALAR);

        uint256 expectedStartTime = block.timestamp;
        uint256 expectedEndTime = expectedStartTime + DISTRIBUTION_FREQUENCY_SCALAR;
        uint256 expectedAmount = realData[0].expectedUsualDist;

        distributionModule.distributeUsualToBuckets(realData[0].ratet, realData[0].p90Rate);

        assertTrue(usualSPMock.wasStartRewardDistributionCalled());
        assertEq(usualSPMock.calledWithStartTime(), expectedStartTime);
        assertEq(usualSPMock.calledWithEndTime(), expectedEndTime);
        assertApproxEqRel(usualSPMock.calledWithAmount(), expectedAmount, 1e15);
    }

    function test_DistributeUsualToBuckets_Should_Emit_UsualAllocatedForUsualStar()
        external
        useUsualStarMock
        setBucketsDistribution(0, 0, BASIS_POINT_BASE)
        calledByDistributionOperatorRole
    {
        setUpTestData();
        skip(DISTRIBUTION_FREQUENCY_SCALAR);

        vm.expectEmit(false, false, false, false, address(distributionModule));
        emit UsualAllocatedForUsualStar(realData[0].expectedUsualDist);
        distributionModule.distributeUsualToBuckets(realData[0].ratet, realData[0].p90Rate);
    }

    function test_DistributeUsualToBuckets_Should_Not_Call_UsualStarWhenTheresNoDistributionForIt()
        external
        useUsualStarMock
        setBucketDistributionToOnlyOffChainBuckets
        calledByDistributionOperatorRole
    {
        setUpTestData();
        skip(DISTRIBUTION_FREQUENCY_SCALAR);

        distributionModule.distributeUsualToBuckets(realData[0].ratet, realData[0].p90Rate);

        assertFalse(usualSPMock.wasStartRewardDistributionCalled());
    }

    function test_DistributeUsualToBuckets_Should_MintTokensToUsualX()
        external
        useUsualStarMock
        useUsualXMock
        setBucketsDistribution(0, BASIS_POINT_BASE, 0)
        calledByDistributionOperatorRole
    {
        setUpTestData();

        uint256 usualXBalanceBefore = usualToken.balanceOf(address(usualXMock));

        skip(DISTRIBUTION_FREQUENCY_SCALAR);
        distributionModule.distributeUsualToBuckets(realData[0].ratet, realData[0].p90Rate);

        uint256 usualXBalanceAfter = usualToken.balanceOf(address(usualXMock));

        assertApproxEqRel(
            usualXBalanceAfter - usualXBalanceBefore, realData[0].expectedUsualDist, 1e15
        );
    }

    function test_DistributeUsualToBuckets_Should_StartDistributionInUsualX()
        external
        useUsualStarMock
        useUsualXMock
        setBucketsDistribution(0, BASIS_POINT_BASE, 0)
        calledByDistributionOperatorRole
    {
        setUpTestData();
        skip(DISTRIBUTION_FREQUENCY_SCALAR);

        uint256 expectedStartTime = block.timestamp;
        uint256 expectedEndTime = expectedStartTime + DISTRIBUTION_FREQUENCY_SCALAR;
        uint256 expectedYieldAmount = realData[0].expectedUsualDist;

        distributionModule.distributeUsualToBuckets(realData[0].ratet, realData[0].p90Rate);

        assertTrue(usualXMock.wasStartYieldDistributionCalled());
        assertEq(usualXMock.calledWithStartTime(), expectedStartTime);
        assertEq(usualXMock.calledWithEndTime(), expectedEndTime);
        assertApproxEqRel(usualXMock.calledWithYieldAmount(), expectedYieldAmount, 1e15);
    }

    function test_DistributeUsualToBuckets_Should_Emit_UsualAllocatedForUsualX()
        external
        useUsualStarMock
        useUsualXMock
        setBucketsDistribution(0, BASIS_POINT_BASE, 0)
        calledByDistributionOperatorRole
    {
        setUpTestData();
        skip(DISTRIBUTION_FREQUENCY_SCALAR);

        vm.expectEmit(false, false, false, false, address(distributionModule));
        emit UsualAllocatedForUsualX(realData[0].expectedUsualDist);
        distributionModule.distributeUsualToBuckets(realData[0].ratet, realData[0].p90Rate);
    }

    function test_DistributeUsualToBuckets_Should_Not_Call_UsualXWhenTheresNoDistributionForIt()
        external
        useUsualXMock
        setBucketDistributionToOnlyOffChainBuckets
        calledByDistributionOperatorRole
    {
        setUpTestData();
        skip(DISTRIBUTION_FREQUENCY_SCALAR);

        distributionModule.distributeUsualToBuckets(realData[0].ratet, realData[0].p90Rate);

        assertFalse(usualXMock.wasStartYieldDistributionCalled());
    }

    function test_DistributeUsualToBuckets_Should_Work()
        external
        useUsualStarMock
        useUsualXMock
        calledByDistributionOperatorRole
    {
        setUpTestData();

        uint256 usualStarBalanceBefore = usualToken.balanceOf(address(usualSPMock));
        uint256 usualXBalanceBefore = usualToken.balanceOf(address(usualXMock));
        uint256 mintCapBefore = distributionModule.getOffChainDistributionMintCap();

        (,,,,,,, uint256 usualPShare, uint256 usualStarShare) =
            distributionModule.getBucketsDistribution();
        uint256 offChainBucketsShare = BASIS_POINT_BASE - usualPShare - usualStarShare;

        skip(DISTRIBUTION_FREQUENCY_SCALAR);
        distributionModule.distributeUsualToBuckets(realData[0].ratet, realData[0].p90Rate);

        uint256 usualStarBalanceAfter = usualToken.balanceOf(address(usualSPMock));
        uint256 usualXBalanceAfter = usualToken.balanceOf(address(usualXMock));
        uint256 mintCapAfter = distributionModule.getOffChainDistributionMintCap();

        uint256 expectedUsualStarBalance =
            Math.mulDiv(realData[0].expectedUsualDist, usualPShare, BPS_SCALAR, Math.Rounding.Floor);
        uint256 expectedUsualXBalance =
            Math.mulDiv(realData[0].expectedUsualDist, usualPShare, BPS_SCALAR, Math.Rounding.Floor);
        uint256 expectedMintCap = Math.mulDiv(
            realData[0].expectedUsualDist, offChainBucketsShare, BPS_SCALAR, Math.Rounding.Floor
        );

        assertApproxEqRel(
            usualStarBalanceAfter - usualStarBalanceBefore, expectedUsualStarBalance, 1e15
        );
        assertApproxEqRel(usualXBalanceAfter - usualXBalanceBefore, expectedUsualXBalance, 1e15);
        assertApproxEqRel(mintCapAfter - mintCapBefore, expectedMintCap, 1e15);
        assertEq(distributionModule.getLastOnChainDistributionTimestamp(), block.timestamp);
    }

    function test_DistributeUsualToBuckets_Should_Emit_UsualAllocatedForOffChainClaim()
        external
        setBucketDistributionToOnlyOffChainBuckets
        calledByDistributionOperatorRole
    {
        setUpTestData();
        skip(DISTRIBUTION_FREQUENCY_SCALAR);

        vm.expectEmit(false, false, false, false, address(distributionModule));
        emit UsualAllocatedForOffChainClaim(realData[0].expectedUsualDist);
        distributionModule.distributeUsualToBuckets(realData[0].ratet, realData[0].p90Rate);
    }

    /*//////////////////////////////////////////////////////////////
                            6. Pausable
    //////////////////////////////////////////////////////////////*/
    function test_DistributionModuleCanBePausedByPausingRole() external calledByPausingRole {
        distributionModule.pause();
        assertTrue(distributionModule.paused());
    }

    function test_DistributionModuleCanBeOnlyPausedByPausingRole(address caller) external {
        vm.assume(caller != address(pauser));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        distributionModule.pause();
    }

    function test_DistributionModuleCanBeUnpausedByDefaultAdminRole()
        external
        modulePaused
        calledByDefaultAdminRole
    {
        distributionModule.unpause();
        assertFalse(distributionModule.paused());
    }

    function test_DistributionModuleCanBeOnlyUnpausedByDefaultAdminRole(address caller) external {
        vm.assume(caller != address(admin));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        distributionModule.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            7. QUEUE OFF-CHAIN DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    function test_QueueOffChainDistributionCanBeOnlyCalledByDistributionOperatorRole() external {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        distributionModule.queueOffChainUsualDistribution(FIRST_MERKLE_ROOT);
    }

    function test_QueueOffChainDistribution_Should_RevertWhenPaused()
        external
        modulePaused
        calledByDistributionOperatorRole
    {
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        distributionModule.queueOffChainUsualDistribution(FIRST_MERKLE_ROOT);
    }

    function test_QueueOffChainDistribution_Should_RevertWhenRootIsZero()
        external
        calledByDistributionOperatorRole
    {
        vm.expectRevert(abi.encodeWithSelector(NullMerkleRoot.selector));
        distributionModule.queueOffChainUsualDistribution(bytes32(0));
    }

    function test_QueueOffChainDistribution_Should_EmitEvent()
        external
        calledByDistributionOperatorRole
    {
        vm.expectEmit();
        emit OffChainDistributionQueued(block.timestamp, FIRST_MERKLE_ROOT);
        distributionModule.queueOffChainUsualDistribution(FIRST_MERKLE_ROOT);
    }

    function test_QueueOffChainDistribution_Should_AddItToQueue()
        external
        calledByDistributionOperatorRole
    {
        distributionModule.queueOffChainUsualDistribution(FIRST_MERKLE_ROOT);

        IDistributionModule.QueuedOffChainDistribution[] memory queue =
            distributionModule.getOffChainDistributionQueue();

        assertEq(queue.length, 1);
        assertEq(queue[0].timestamp, block.timestamp);
        assertEq(queue[0].merkleRoot, FIRST_MERKLE_ROOT);
    }

    /*//////////////////////////////////////////////////////////////
                            8. APPROVE OFF-CHAIN DISTRIBUTION
    //////////////////////////////////////////////////////////////*/
    function test_ApproveUnchallengedDistributionCanOnlyBeCalledByAnyOne(address caller)
        external
        distributionsQueuedFor(9)
    {
        vm.assume(caller != address(distributionOperator));

        vm.prank(caller);
        distributionModule.approveUnchallengedOffChainDistribution();
    }

    function test_ApproveUnchallengedDistribution_Should_RevertWhenPaused() external modulePaused {
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        distributionModule.approveUnchallengedOffChainDistribution();
    }

    function test_ApproveUnchallengedDistribution_Should_RemoveDistributionFromQueueThatAreOlderThanChallengePeriod(
    ) external distributionsQueuedFor(9) {
        distributionModule.approveUnchallengedOffChainDistribution();

        IDistributionModule.QueuedOffChainDistribution[] memory queue =
            distributionModule.getOffChainDistributionQueue();

        assertEq(queue.length, 7);
    }

    function test_ApproveUnchallengedDistribution_Should_UpdateCurrentDistributionData() external {
        uint256 expectedTimestamp = block.timestamp;
        vm.prank(distributionOperator);
        distributionModule.queueOffChainUsualDistribution(FIRST_MERKLE_ROOT);
        skip(7 days);

        distributionModule.approveUnchallengedOffChainDistribution();

        (uint256 timestamp, bytes32 merkleRoot) = distributionModule.getOffChainDistributionData();
        assertEq(timestamp, expectedTimestamp);
        assertEq(merkleRoot, FIRST_MERKLE_ROOT);
    }

    function test_ApproveUnchallengedDistribution_Should_UpdateCurrentDistributionDataWithTheNewestDistribution(
    ) external {
        vm.prank(distributionOperator);
        distributionModule.queueOffChainUsualDistribution(FIRST_MERKLE_ROOT);
        skip(DISTRIBUTION_FREQUENCY_SCALAR);

        uint256 expectedTimestamp = block.timestamp;
        vm.prank(distributionOperator);
        distributionModule.queueOffChainUsualDistribution(SECOND_MERKLE_ROOT);

        skip(7 days);

        distributionModule.approveUnchallengedOffChainDistribution();

        (uint256 timestamp, bytes32 merkleRoot) = distributionModule.getOffChainDistributionData();
        assertEq(timestamp, expectedTimestamp);
        assertEq(merkleRoot, SECOND_MERKLE_ROOT);
    }

    function test_ApproveUnchallengedDistribution_Should_RevertWhenThereIsNoDistributionInQueue()
        external
    {
        vm.expectRevert(abi.encodeWithSelector(NoOffChainDistributionToApprove.selector));
        distributionModule.approveUnchallengedOffChainDistribution();
    }

    function test_ApproveUnchallengedDistribution_Should_RevertWhenThereIsNoDistributionInQueueOlderThanChallengePeriod(
    ) external distributionsQueuedFor(5) {
        vm.expectRevert(abi.encodeWithSelector(NoOffChainDistributionToApprove.selector));
        distributionModule.approveUnchallengedOffChainDistribution();
    }

    function test_ApproveUnchallengedDistribution_Should_RevertWhenThereIsNoDistributionInQueueThatIsUnchallenged(
    ) external challengedDistributionQueued(5) {
        vm.expectRevert(abi.encodeWithSelector(NoOffChainDistributionToApprove.selector));
        distributionModule.approveUnchallengedOffChainDistribution();
    }

    /*//////////////////////////////////////////////////////////////
                            9. CLAIM OFF-CHAIN DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    function test_ClaimOffChainDistribution_Should_RevertWhenPaused() external modulePaused {
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        distributionModule.claimOffChainDistribution(
            alice, aliceAmountInFirstMerkleTree, _aliceProofForFirstMerkleTree()
        );
    }

    function test_ClaimOffChainDistribution_Should_RevertWhenTheresNoApprovedDistribution()
        external
    {
        vm.expectRevert(abi.encodeWithSelector(NoTokensToClaim.selector));
        distributionModule.claimOffChainDistribution(
            alice, aliceAmountInFirstMerkleTree, _aliceProofForFirstMerkleTree()
        );
    }

    function test_ClaimOffChainDistribution_Should_RevertWhenAmountIsZero() external {
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        distributionModule.claimOffChainDistribution(alice, 0, _aliceProofForFirstMerkleTree());
    }

    function test_ClaimOffChainDistribution_Should_RevertWhenAddressIsZero() external {
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        distributionModule.claimOffChainDistribution(
            address(0), aliceAmountInFirstMerkleTree, _aliceProofForFirstMerkleTree()
        );
    }

    function test_ClaimOffChainDistribution_Should_RevertWhenInvalidProofIsProvided()
        external
        queueAndApproveDistribution(FIRST_MERKLE_ROOT)
    {
        vm.expectRevert(abi.encodeWithSelector(InvalidProof.selector));
        distributionModule.claimOffChainDistribution(
            alice, aliceAmountInFirstMerkleTree, _aliceProofForSecondMerkleTree()
        );
    }

    function test_ClaimOffChainDistribution_Should_RevertWhenWrongAmountIsProvided()
        external
        queueAndApproveDistribution(FIRST_MERKLE_ROOT)
    {
        uint256 invalidAmount = 100e18;

        vm.expectRevert(abi.encodeWithSelector(InvalidProof.selector));
        distributionModule.claimOffChainDistribution(
            alice, invalidAmount, _aliceProofForFirstMerkleTree()
        );
    }

    function test_ClaimOffChainDistribution_Should_RevertWhenItHasNotEnoughUsualToClaim()
        external
        queueAndApproveDistribution(FIRST_MERKLE_ROOT)
    {
        vm.expectRevert(abi.encodeWithSelector(NoTokensToClaim.selector));
        distributionModule.claimOffChainDistribution(
            alice, aliceAmountInFirstMerkleTree, _aliceProofForFirstMerkleTree()
        );
    }

    function test_ClaimOffChainDistribution_Should_RevertWhenClaimedTwice()
        external
        distributeUsualForTestData
        queueAndApproveDistribution(FIRST_MERKLE_ROOT)
    {
        distributionModule.claimOffChainDistribution(
            alice, aliceAmountInFirstMerkleTree, _aliceProofForFirstMerkleTree()
        );

        vm.expectRevert(abi.encodeWithSelector(NoTokensToClaim.selector));
        distributionModule.claimOffChainDistribution(
            alice, aliceAmountInFirstMerkleTree, _aliceProofForFirstMerkleTree()
        );
    }

    function test_ClaimOffChainDistribution_Should_UpdateTokensClaimedByAccount()
        external
        distributeUsualForTestData
        queueAndApproveDistribution(FIRST_MERKLE_ROOT)
    {
        distributionModule.claimOffChainDistribution(
            alice, aliceAmountInFirstMerkleTree, _aliceProofForFirstMerkleTree()
        );
        assertEq(distributionModule.getOffChainTokensClaimed(alice), aliceAmountInFirstMerkleTree);
    }

    function test_ClaimOffChainDistribution_Should_UpdateTotalMintCap()
        external
        distributeUsualForTestData
        queueAndApproveDistribution(FIRST_MERKLE_ROOT)
    {
        uint256 initialMintCap = distributionModule.getOffChainDistributionMintCap();
        uint256 expectedMintCap = initialMintCap - aliceAmountInFirstMerkleTree;

        distributionModule.claimOffChainDistribution(
            alice, aliceAmountInFirstMerkleTree, _aliceProofForFirstMerkleTree()
        );

        assertEq(distributionModule.getOffChainDistributionMintCap(), expectedMintCap);
    }

    function test_ClaimOffChainDistribution_Should_ReceiveOnlyTokensThatWereNotAlreadyClaimed()
        external
        distributeUsualForTestData
        queueAndApproveDistribution(FIRST_MERKLE_ROOT)
        aliceClaimedFromApprovedFirstMerkleTree
        queueAndApproveDistribution(SECOND_MERKLE_ROOT)
    {
        distributionModule.claimOffChainDistribution(
            alice, aliceAmountInSecondMerkleTree, _aliceProofForSecondMerkleTree()
        );

        assertEq(distributionModule.getOffChainTokensClaimed(alice), aliceAmountInSecondMerkleTree);
    }

    function test_ClaimOffChainDistribution_Should_TransferOnlyTokensThatWereNotAlreadyClaimed()
        external
        distributeUsualForTestData
        queueAndApproveDistribution(FIRST_MERKLE_ROOT)
        aliceClaimedFromApprovedFirstMerkleTree
        queueAndApproveDistribution(SECOND_MERKLE_ROOT)
    {
        uint256 expectedTransferredAmount =
            aliceAmountInSecondMerkleTree - aliceAmountInFirstMerkleTree;

        uint256 aliceBalanceBefore = usualToken.balanceOf(alice);

        distributionModule.claimOffChainDistribution(
            alice, aliceAmountInSecondMerkleTree, _aliceProofForSecondMerkleTree()
        );
        uint256 aliceBalanceAfter = usualToken.balanceOf(alice);

        assertEq(aliceBalanceAfter - aliceBalanceBefore, expectedTransferredAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            10. CHALLENGE OFF-CHAIN DISTRIBUTION
    //////////////////////////////////////////////////////////////*/
    /// 10.1 challengeOffChainDistribution
    function test_ChallengeOffChainDistribution_Should_RevertWhenNotCalledByChallengerRole()
        external
    {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        distributionModule.challengeOffChainDistribution(block.timestamp);
    }

    function test_ChallengeOffChainDistribution_Should_RevertWhenPaused()
        external
        modulePaused
        calledByDistributionChallengerRole
    {
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        distributionModule.challengeOffChainDistribution(block.timestamp);
    }

    function test_ChallengeOffChainDistribution_Should_MarkAllQueuedDistributionsOlderThanTimestampAsChallenged(
    ) external distributionsQueuedFor(7) {
        uint256 timestampToChallengeFrom = block.timestamp + 1;
        skip(DISTRIBUTION_FREQUENCY_SCALAR);
        vm.prank(distributionOperator);
        distributionModule.queueOffChainUsualDistribution(FIRST_MERKLE_ROOT);

        vm.prank(distributionChallenger);
        distributionModule.challengeOffChainDistribution(timestampToChallengeFrom);

        IDistributionModule.QueuedOffChainDistribution[] memory queue =
            distributionModule.getOffChainDistributionQueue();

        // The first one and the last one shouldn't be challenged
        assertEq(queue.length, 2);
    }

    function test_ChallengeOffChainDistribution_Should_not_work_WhenAfterChallengePeriod()
        external
        distributionsQueuedFor(7)
        calledByDistributionChallengerRole
    {
        skip(USUAL_DISTRIBUTION_CHALLENGE_PERIOD);

        distributionModule.challengeOffChainDistribution(block.timestamp);

        IDistributionModule.QueuedOffChainDistribution[] memory queue =
            distributionModule.getOffChainDistributionQueue();

        // No changes should be made to the queue
        assertEq(queue.length, 7);
    }

    /*//////////////////////////////////////////////////////////////
                11. Emergency reset of distribution queue    
    //////////////////////////////////////////////////////////////*/
    function test_ResetOffChainDistributionQueue_Should_RevertWhenNotCalledByOperatorRole()
        external
    {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        distributionModule.resetOffChainDistributionQueue();
    }

    function test_ResetOffChainDistributionQueue_Should_RevertWhenPaused()
        external
        modulePaused
        calledByDistributionOperatorRole
    {
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        distributionModule.resetOffChainDistributionQueue();
    }

    function test_ResetOffChainDistributionQueue_Should_RemoveAllDistributionsFromQueue()
        external
        distributionsQueuedFor(10_000)
        calledByDistributionOperatorRole
    {
        distributionModule.resetOffChainDistributionQueue();
        IDistributionModule.QueuedOffChainDistribution[] memory queue =
            distributionModule.getOffChainDistributionQueue();
        assertEq(queue.length, 0);
    }

    function test_ResetOffChainDistributionQueue_Should_NotBreakNewEntries()
        external
        distributionsQueuedFor(7)
        calledByDistributionOperatorRole
    {
        distributionModule.resetOffChainDistributionQueue();

        distributionModule.queueOffChainUsualDistribution(FIRST_MERKLE_ROOT);
        IDistributionModule.QueuedOffChainDistribution[] memory queue =
            distributionModule.getOffChainDistributionQueue();
        assertEq(queue.length, 1);
    }

    function test_GammaCalculationTimingIssue() external calledByDistributionOperatorRole {
        setUpTestData();
        // Values obtained after Spearbit audit fix #15 remediation
        // https://cantina.xyz/code/59e90e58-0170-4747-bda6-72ebeb2d5592/findings/15
        uint256 expectedUsualAllocatedForOffChainClaim0 = 313_159_289_095_890_410_958;
        uint256 expectedUsualAllocatedForOffChainClaim1 = 627_467_786_592_132_712_759;

        // First distribution
        skip(DISTRIBUTION_FREQUENCY_SCALAR);
        vm.expectEmit(address(distributionModule));
        emit UsualAllocatedForOffChainClaim(expectedUsualAllocatedForOffChainClaim0);
        distributionModule.distributeUsualToBuckets(realData[0].ratet, realData[0].p90Rate);

        // Skip 48 hours (2 days)
        skip(2 * DISTRIBUTION_FREQUENCY_SCALAR);

        vm.expectEmit(address(distributionModule));
        emit UsualAllocatedForOffChainClaim(expectedUsualAllocatedForOffChainClaim1);
        // Do the actual distribution
        distributionModule.distributeUsualToBuckets(realData[1].ratet, realData[1].p90Rate);
    }

    function test_poc_claimOffChainDistribution_mintCap() external {
        vm.prank(distributionAllocator);
        distributionModule.setBucketsDistribution(BASIS_POINT_BASE, 0, 0, 0, 0, 0, 0, 0, 0);
        skip(DISTRIBUTION_FREQUENCY_SCALAR);
        // Distribute Usual
        vm.startPrank(distributionOperator);
        distributionModule.distributeUsualToBuckets(30, 30);
        // The mint cap has increased to over 20 tokens
        uint256 mintCap = distributionModule.getOffChainDistributionMintCap();
        assertGt(mintCap, 20e18);
        // Queue and approve first distribution
        distributionModule.queueOffChainUsualDistribution(FIRST_MERKLE_ROOT);
        skip(USUAL_DISTRIBUTION_CHALLENGE_PERIOD + 1);
        distributionModule.approveUnchallengedOffChainDistribution();
        vm.stopPrank();
        // Alice claims 10 tokens from first distribution
        distributionModule.claimOffChainDistribution(
            alice, aliceAmountInFirstMerkleTree, _aliceProofForFirstMerkleTree()
        );
        // Queue and approve second distribution
        vm.startPrank(distributionOperator);
        distributionModule.queueOffChainUsualDistribution(SECOND_MERKLE_ROOT);
        skip(USUAL_DISTRIBUTION_CHALLENGE_PERIOD + 1);
        distributionModule.approveUnchallengedOffChainDistribution();
        vm.stopPrank();
        // Alice should be able to claim from the second distribution
        distributionModule.claimOffChainDistribution(
            alice, aliceAmountInSecondMerkleTree, _aliceProofForSecondMerkleTree()
        );
        // Alice's outstanding claim is less than the remaining mint cap
        uint256 tokensClaimed = distributionModule.getOffChainTokensClaimed(alice);
        uint256 outstandingClaim = aliceAmountInSecondMerkleTree - tokensClaimed;
        assertLt(outstandingClaim, mintCap);
    }
}
