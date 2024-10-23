// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SetupTest} from "test/setup.t.sol";
import {UsualOracle} from "src/oracles/UsualOracle.sol";
import {RwaMock} from "src/mock/rwaMock.sol";
import {USYC, ORACLE_UPDATER} from "src/mock/constants.sol";
import {BASIS_POINT_BASE} from "src/constants.sol";
import {
    SameValue,
    OracleNotInitialized,
    OracleNotWorkingNotCurrent,
    InvalidTimeout
} from "src/errors.sol";

contract UsualOracleTest is SetupTest {
    event Initialized(uint64);

    function setUp() public override {
        uint256 forkId = vm.createFork("eth");
        vm.selectFork(forkId);
        super.setUp();
        vm.startPrank(admin);
        registryAccess.grantRole(ORACLE_UPDATER, hashnote);
        dataPublisher.addWhitelistPublisher(USYC, hashnote);
        vm.stopPrank();
        // Initialize USYC PriceFeed
    }

    function testConstructor() public {
        vm.expectEmit();
        emit Initialized(type(uint64).max);

        UsualOracle usualOracle = new UsualOracle();
        assertTrue(address(usualOracle) != address(0));
    }

    function testInitializeFailIfTokenIsNull() public {
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        vm.prank(admin);
        usualOracle.initializeTokenOracle(address(0), 1 days, false);
    }

    function testInitializeFailIfTimeoutIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidTimeout.selector));
        vm.prank(admin);
        usualOracle.initializeTokenOracle(USYC, 0, false);
    }

    function testInitializeFailOracleNotWorkingNotCurrent() public {
        vm.startPrank(hashnote);
        dataPublisher.publishData(USYC, 0.9e6);
        vm.stopPrank();
        // wait four days
        skip(4 days);
        vm.expectRevert(abi.encodeWithSelector(OracleNotWorkingNotCurrent.selector));
        vm.prank(admin);
        usualOracle.initializeTokenOracle(USYC, 1 days, false);
    }

    function initializeUSYCPriceFeed() public {
        vm.startPrank(hashnote);
        dataPublisher.publishData(USYC, 0.9e6);
        dataPublisher.publishData(USYC, 1e6);
        vm.stopPrank();

        vm.prank(admin);
        usualOracle.initializeTokenOracle(USYC, 1 days, false);
        dataPublisher.latestRoundData(USYC);
        dataPublisher.getRoundData(USYC, 1);
    }

    function testGetPrice() public {
        initializeUSYCPriceFeed();
        assertEq(usualOracle.getPrice(USYC), 1e18, "Price should be 1");
    }

    function testGetQuote() public {
        initializeUSYCPriceFeed();
        assertEq(usualOracle.getQuote(USYC, 1156e6), 1156e6, "Price should be 1");
    }

    function testGetPriceWith18Decimals() public {
        vm.prank(admin);
        rwaFactory.createRwa("DeathNote US Yield Coin", "X-USYC", 18);

        RwaMock fakeRWA = RwaMock(rwaFactory.getRwaFromSymbol("X-USYC"));

        assertEq(fakeRWA.decimals(), 18);
        vm.prank(address(admin));
        dataPublisher.addWhitelistPublisher(address(fakeRWA), hashnote);

        vm.startPrank(hashnote);
        dataPublisher.publishData(address(fakeRWA), 0.9e18);
        dataPublisher.publishData(address(fakeRWA), 1e18);
        vm.stopPrank();

        vm.prank(admin);
        usualOracle.initializeTokenOracle(address(fakeRWA), 1 days, false);
        dataPublisher.latestRoundData(address(fakeRWA));
        dataPublisher.getRoundData(address(fakeRWA), 1);
        assertEq(usualOracle.getPrice(address(fakeRWA)), 1e18);
    }

    function testGetPriceWith27Decimals() public {
        vm.prank(admin);
        rwaFactory.createRwa("DeathNote US Yield Coin", "X-USYC", 18);

        RwaMock fakeRWA = RwaMock(rwaFactory.getRwaFromSymbol("X-USYC"));
        fakeRWA.setDecimals(27);
        assertEq(fakeRWA.decimals(), 27);
        vm.prank(address(admin));
        dataPublisher.addWhitelistPublisher(address(fakeRWA), hashnote);

        vm.startPrank(hashnote);
        dataPublisher.publishData(address(fakeRWA), 0.9e27);
        dataPublisher.publishData(address(fakeRWA), 1e27);
        vm.stopPrank();

        vm.prank(admin);
        usualOracle.initializeTokenOracle(address(fakeRWA), 1 days, false);
        dataPublisher.latestRoundData(address(fakeRWA));
        dataPublisher.getRoundData(address(fakeRWA), 1);
        assertEq(usualOracle.getPrice(address(fakeRWA)), 1e18);
    }

    function testGetPriceOracleFailNotInit() public {
        vm.startPrank(hashnote);
        dataPublisher.publishData(USYC, 0.9e6);
        dataPublisher.publishData(USYC, 1e6);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(OracleNotInitialized.selector));
        usualOracle.getPrice(USYC);
    }

    function testGetPriceChangeWithinRange(uint256 amount) public {
        amount = bound(amount, 100, type(uint128).max);
        vm.startPrank(hashnote);
        dataPublisher.publishData(USYC, int256(amount * 10 / 9));
        dataPublisher.publishData(USYC, int256(amount));
        vm.stopPrank();

        vm.prank(admin);
        usualOracle.initializeTokenOracle(USYC, 1 days, false);

        assertEq(usualOracle.getPrice(USYC), amount * 1e12, "Price should be amount");
        vm.prank(hashnote);
        // +50% change
        uint256 amountAlmostPlusFiftyPercent = amount + amount / 2 - 1;
        dataPublisher.publishData(USYC, int256(amountAlmostPlusFiftyPercent));
        assertEq(
            usualOracle.getPrice(USYC),
            amountAlmostPlusFiftyPercent * 1e12,
            "Price should be amount +49.99%"
        );
        // +10% change
        uint256 amountPlusTenPercent = amount + amount / 10;
        vm.prank(hashnote);
        dataPublisher.publishData(USYC, int256(amountPlusTenPercent));
        assertEq(
            usualOracle.getPrice(USYC), amountPlusTenPercent * 1e12, "Price should be amount +10%"
        );
        // +100% change
        uint256 amountAlmostPlusOneHundredPercent = amountPlusTenPercent * 2;
        vm.prank(hashnote);
        dataPublisher.publishData(USYC, int256(amountAlmostPlusOneHundredPercent));
        // we get the last good price
        assertEq(
            usualOracle.getPrice(USYC),
            amountAlmostPlusOneHundredPercent * 1e12,
            "Price should be amount +100%"
        );
    }

    function testGetPriceChangeAboveMax() public {
        initializeUSYCPriceFeed();

        assertEq(usualOracle.getPrice(USYC), 1e18, "Price should be 1");
        vm.prank(hashnote);
        dataPublisher.publishData(USYC, 1.49999e6);
        assertEq(usualOracle.getPrice(USYC), 1.49999e18, "Price should be 1.49999");
        vm.prank(hashnote);
        dataPublisher.publishData(USYC, 1.1e6);
        assertEq(usualOracle.getPrice(USYC), 1.1e18, "Price should be 1.1");
        // +50% change
        vm.prank(hashnote);
        dataPublisher.publishData(USYC, 1.650001e6);
        // we get the last good price
        assertEq(usualOracle.getPrice(USYC), 1.650001e18, "Price should be 1.65");
    }

    function testGetPriceChangeAboveMaxTwiceShouldWork() public {
        testGetPriceChangeAboveMax();
        // +50% change again should work
        vm.prank(hashnote);
        dataPublisher.publishData(USYC, 1.650001e6);
        // we now have the new price
        assertEq(usualOracle.getPrice(USYC), 1.650001e18, "Price should be 1.65");
    }

    function testGetPriceDecreaseBelowMaxShouldWork() public {
        testGetPriceChangeAboveMaxTwiceShouldWork();
        // -45% change should work
        vm.prank(hashnote);
        dataPublisher.publishData(USYC, 0.95e6);
        // we now have the new price
        assertEq(usualOracle.getPrice(USYC), 0.95e18, "Price should be 0.95");
    }

    function testGetPriceOracleBroken() public {
        initializeUSYCPriceFeed();
        vm.prank(hashnote);
        dataPublisher.publishData(USYC, 0);

        vm.expectRevert(abi.encodeWithSelector(OracleNotWorkingNotCurrent.selector));
        usualOracle.getPrice(USYC);
    }

    // test setMaxDepegThreshold revert when caller is not usual tech team
    function testSetMaxDepegThresholdRevertWhenNotAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        usualOracle.setMaxDepegThreshold(BASIS_POINT_BASE);
    }

    function testSetMaxDepegThresholdRevertIfSameValue() public {
        assertEq(usualOracle.getMaxDepegThreshold(), 100);
        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        vm.prank(address(admin));
        usualOracle.setMaxDepegThreshold(100);
    }

    // test setMaxDepegThreshold should work
    function testSetMaxDepegThreshold() public {
        assertEq(usualOracle.getMaxDepegThreshold(), 100);
        vm.prank(address(admin));
        usualOracle.setMaxDepegThreshold(BASIS_POINT_BASE);
        assertEq(
            usualOracle.getMaxDepegThreshold(), BASIS_POINT_BASE, "Max depeg threshold should be 1"
        );
    }
}
