// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SetupTest} from "test/setup.t.sol";
import {ClassicalOracle} from "src/oracles/ClassicalOracle.sol";
import {ONE_WEEK, BASIS_POINT_BASE} from "src/constants.sol";
import {USDC, USDC_PRICE_FEED_MAINNET} from "src/mock/constants.sol";
import {IAggregator} from "src/interfaces/oracles/IAggregator.sol";
import {
    InvalidTimeout,
    SameValue,
    NullAddress,
    OracleNotWorkingNotCurrent,
    OracleNotInitialized,
    DepegThresholdTooHigh,
    StablecoinDepeg
} from "src/errors.sol";

contract ClassicalOracleTest is SetupTest, ClassicalOracle {
    address constant FRAX_PRICE_FEED_MAINNET = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;
    address constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    function setUp() public override {
        uint256 forkId = vm.createFork("eth");
        vm.selectFork(forkId);
        super.setUp();
        classicalOracle = new ClassicalOracle();
        _resetInitializerImplementation(address(classicalOracle));
        classicalOracle.initialize(address(registryContract));
        // Initialize USDC PriceFeed
        vm.prank(admin);
        classicalOracle.initializeTokenOracle(USDC, USDC_PRICE_FEED_MAINNET, 1 days, true);

        // Initialize FRAX PriceFeed
        vm.prank(admin);
        classicalOracle.initializeTokenOracle(FRAX, FRAX_PRICE_FEED_MAINNET, 1 days, true);
    }

    function testConstructor() public {
        vm.expectEmit();
        emit Initialized(type(uint64).max);

        ClassicalOracle oracle = new ClassicalOracle();
        assertTrue(address(oracle) != address(0));
    }

    function testInitializeTokenOracleFail() public {
        // Initialize USDC PriceFeed
        vm.expectRevert(abi.encodeWithSelector(InvalidTimeout.selector));
        vm.prank(admin);
        classicalOracle.initializeTokenOracle(USDC, USDC_PRICE_FEED_MAINNET, 0 days, true);

        vm.expectRevert(abi.encodeWithSelector(InvalidTimeout.selector));
        vm.prank(admin);
        classicalOracle.initializeTokenOracle(USDC, USDC_PRICE_FEED_MAINNET, ONE_WEEK + 1, true);

        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        vm.prank(admin);
        classicalOracle.initializeTokenOracle(address(0), USDC_PRICE_FEED_MAINNET, 1 days, true);

        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        vm.prank(admin);
        classicalOracle.initializeTokenOracle(USDC, address(0), 1 days, true);

        vm.expectRevert(abi.encodeWithSelector(OracleNotWorkingNotCurrent.selector));
        vm.prank(admin);
        classicalOracle.initializeTokenOracle(USDC, USDC_PRICE_FEED_MAINNET, 1 seconds, false);

        vm.expectRevert();
        vm.prank(admin);
        classicalOracle.initializeTokenOracle(address(0x1), address(0x2), 1 days, false);
    }

    function exposedLatestRoundData(address token) public view returns (uint256, uint256) {
        return _latestRoundData(token);
    }

    function testLatestRoundDataShouldFail() public {
        vm.expectRevert(abi.encodeWithSelector(OracleNotInitialized.selector));
        exposedLatestRoundData(USDC);
    }

    function testInitializeTokenOracleFailWhenUpdatedAtIsNull() public {
        // Mock USDC PriceFeed
        uint80 roundId = 2;
        int256 answer = 1e6;
        uint256 startedAt = 10;
        uint256 updatedAt = 0;
        uint80 answeredInRound = 1;
        vm.mockCall(
            USDC_PRICE_FEED_MAINNET,
            abi.encodeWithSelector(IAggregator.latestRoundData.selector),
            abi.encode(roundId, answer, startedAt, updatedAt, answeredInRound)
        );

        vm.expectRevert(abi.encodeWithSelector(OracleNotWorkingNotCurrent.selector));
        vm.prank(admin);
        classicalOracle.initializeTokenOracle(USDC, USDC_PRICE_FEED_MAINNET, 1 days, true);
    }

    function testGetPriceShouldFailWhenOracleFailUpdate() public {
        // Mock USDC PriceFeed
        // updatedAt is null
        uint80 roundId = 2;
        int256 answer = 1e6;
        uint256 startedAt = 10;
        uint256 updatedAt = 0;
        uint80 answeredInRound = 1;
        vm.mockCall(
            USDC_PRICE_FEED_MAINNET,
            abi.encodeWithSelector(IAggregator.latestRoundData.selector),
            abi.encode(roundId, answer, startedAt, updatedAt, answeredInRound)
        );
        vm.expectRevert(abi.encodeWithSelector(OracleNotWorkingNotCurrent.selector));
        classicalOracle.getPrice(USDC);
    }

    function testGetPriceShouldFailWhenOracleUpdateIsIncorrect() public {
        // Mock USDC PriceFeed
        // updatedAt is null
        uint80 roundId = 2;
        int256 answer = 1e6;
        uint256 startedAt = 10;
        uint256 updatedAt = block.timestamp + 1000;
        uint80 answeredInRound = 1;
        vm.mockCall(
            USDC_PRICE_FEED_MAINNET,
            abi.encodeWithSelector(IAggregator.latestRoundData.selector),
            abi.encode(roundId, answer, startedAt, updatedAt, answeredInRound)
        );
        vm.expectRevert(abi.encodeWithSelector(OracleNotWorkingNotCurrent.selector));
        classicalOracle.getPrice(USDC);
    }

    function testGetPriceShouldFailWhenOracleStall() public {
        // Mock USDC PriceFeed
        uint80 roundId = 2;
        int256 answer = 1e8;
        uint256 startedAt = 10;
        uint256 updatedAt = block.timestamp - 1;
        uint80 answeredInRound = 1;
        vm.mockCall(
            USDC_PRICE_FEED_MAINNET,
            abi.encodeWithSelector(IAggregator.latestRoundData.selector),
            abi.encode(roundId, answer, startedAt, updatedAt, answeredInRound)
        );

        // initialize with a 1 day timeout
        vm.prank(admin);
        classicalOracle.initializeTokenOracle(USDC, USDC_PRICE_FEED_MAINNET, 1 days, true);
        assertEq(classicalOracle.getPrice(USDC), 1e18, "price should be 1");

        // skip 2 days
        uint256 time = 2 days;
        skip(time);
        vm.expectRevert(abi.encodeWithSelector(OracleNotWorkingNotCurrent.selector));
        classicalOracle.getPrice(USDC);
    }

    function testInitializeFailNullAddress() public {
        _resetInitializerImplementation(address(classicalOracle));
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        vm.prank(admin);
        classicalOracle.initialize(address(0));
    }

    function testGetPrice() public view {
        assertApproxEqRel(classicalOracle.getPrice(USDC), 1e18, 0.01 ether, "Price should be 1");
    }

    function testGetQuote() public view {
        assertApproxEqRel(classicalOracle.getQuote(USDC, 1000e6), 1000e6, 0.01 ether);
    }

    function testGetQuote18Decimals() public view {
        assertApproxEqRel(classicalOracle.getQuote(FRAX, 1000e18), 1000e18, 0.01 ether);
    }

    // test setMaxDepegThreshold revert when caller is not usual tech team
    function testSetMaxDepegThresholdRevertWhenNotAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        classicalOracle.setMaxDepegThreshold(100);
    }

    function testSetMaxDepegThresholdRevertIfTooHigh() public {
        assertEq(classicalOracle.getMaxDepegThreshold(), 100);
        vm.expectRevert(abi.encodeWithSelector(DepegThresholdTooHigh.selector));

        vm.prank(admin);
        classicalOracle.setMaxDepegThreshold(BASIS_POINT_BASE + 1);
    }

    function testSetMaxDepegThresholdRevertIfSameValue() public {
        assertEq(classicalOracle.getMaxDepegThreshold(), 100);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        vm.prank(admin);
        classicalOracle.setMaxDepegThreshold(100);
    }

    function testSetMaxDepegThresholdRevertIfTooBig() public {
        assertEq(classicalOracle.getMaxDepegThreshold(), 100);
        vm.expectRevert(abi.encodeWithSelector(DepegThresholdTooHigh.selector));
        vm.prank(admin);
        classicalOracle.setMaxDepegThreshold(BASIS_POINT_BASE + 1);
        assertEq(classicalOracle.getMaxDepegThreshold(), 100);
    }

    // test setMaxDepegThreshold should work
    function testSetMaxDepegThreshold() public {
        assertEq(classicalOracle.getMaxDepegThreshold(), 100);
        vm.prank(admin);
        classicalOracle.setMaxDepegThreshold(BASIS_POINT_BASE);
        assertEq(
            classicalOracle.getMaxDepegThreshold(),
            BASIS_POINT_BASE,
            "Max depeg threshold should be 1"
        );
    }

    function testGetPriceRevertIfDepeg(uint256 newAnswer) public {
        newAnswer = bound(newAnswer, 1, 0.9e8);
        // Mock USDC PriceFeed
        uint80 roundId = 2;
        int256 answer = 1e8;
        uint256 startedAt = 10;
        uint256 updatedAt = block.timestamp - 1;
        uint80 answeredInRound = 1;
        vm.mockCall(
            USDC_PRICE_FEED_MAINNET,
            abi.encodeWithSelector(IAggregator.latestRoundData.selector),
            abi.encode(roundId, answer, startedAt, updatedAt, answeredInRound)
        );

        // initialize with a 1 day timeout
        vm.prank(admin);
        classicalOracle.initializeTokenOracle(USDC, USDC_PRICE_FEED_MAINNET, 1 days, true);
        assertEq(classicalOracle.getPrice(USDC), 1e18, "price should be 1");

        // Mock USDC PriceFeed with depegged value
        roundId = 3;
        startedAt = 10;
        updatedAt = block.timestamp - 1;
        answeredInRound = 2;
        vm.mockCall(
            USDC_PRICE_FEED_MAINNET,
            abi.encodeWithSelector(IAggregator.latestRoundData.selector),
            abi.encode(roundId, newAnswer, startedAt, updatedAt, answeredInRound)
        );
        // skip 2 days
        vm.expectRevert(abi.encodeWithSelector(StablecoinDepeg.selector));
        classicalOracle.getPrice(USDC);
    }
}
