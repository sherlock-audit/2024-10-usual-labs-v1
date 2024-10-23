// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {SetupTest} from "test/setup.t.sol";
import {DataPublisher} from "src/mock/dataPublisher.sol";
import {USDC} from "src/mock/constants.sol";
import {SameValue} from "src/errors.sol";
import {PriceUpdateBlocked} from "src/mock/errors.sol";

contract DataPublisherTest is SetupTest {
    function setUp() public override {
        uint256 forkId = vm.createFork("eth");
        vm.selectFork(forkId);
        super.setUp();
    }

    function testAddPublisherWhitelist() public {
        vm.prank(admin);
        dataPublisher.addWhitelistPublisher(USDC, hashnote);
        vm.prank(admin);
        dataPublisher.addWhitelistPublisher(USDC, admin);
        assertEq(dataPublisher.isWhitelistPublisher(USDC, hashnote), true, "Should be whitelisted");
    }

    function testNotPublisherWhitelist() public view {
        assertEq(
            dataPublisher.isWhitelistPublisher(USDC, hashnote), false, "Should not be whitelisted"
        );
    }

    function testRemovePublisherWhitelist() public {
        testAddPublisherWhitelist();
        vm.prank(admin);
        dataPublisher.removeWhitelistPublisher(USDC, hashnote);
        assertEq(
            dataPublisher.isWhitelistPublisher(USDC, hashnote), false, "Should not be whitelisted"
        );
    }

    function testPublishData() public {
        testAddPublisherWhitelist();
        vm.prank(hashnote);
        dataPublisher.publishData(USDC, 1e18);
    }

    function testGetLastRoundData() public {
        testPublishData();
        (, int256 answer,,) = dataPublisher.latestRoundData(USDC);
        assertEq(answer, 1e18, "Price should be 1");
    }

    function testGetRoundData() public {
        testPublishData();
        (, int256 answer,,) = dataPublisher.getRoundData(USDC, 1);
        assertEq(answer, 1e18, "Price should be 1");
    }

    function testGetLastResponse() public {
        testPublishData();
        DataPublisher.OracleResponse memory resp = dataPublisher.getLastResponse(USDC);
        assertEq(resp.answer, 1e18, "Price should be 1");
    }

    function testGetLastResponseId() public {
        testPublishData();
        DataPublisher.OracleResponse memory resp = dataPublisher.getLastResponseId(USDC, 1);
        assertEq(resp.answer, 1e18, "Price should be 1");
    }

    function testSetBlockAssetPrice() public {
        testPublishData();
        vm.prank(admin);
        dataPublisher.blockAssetPriceUpdate(USDC, true);
        vm.prank(hashnote);
        vm.expectRevert(abi.encodeWithSelector(PriceUpdateBlocked.selector));
        dataPublisher.publishData(USDC, 1.01e18);
        (, int256 answer,,) = dataPublisher.latestRoundData(USDC);
        assertEq(answer, 1e18, "Price shouldn't have been updated and be 1");
    }

    function testSetBlockAssetPriceShouldFailIfSameValue() public {
        testPublishData();
        vm.prank(admin);
        dataPublisher.blockAssetPriceUpdate(USDC, true);

        vm.expectRevert(abi.encodeWithSelector(SameValue.selector));
        vm.prank(admin);
        dataPublisher.blockAssetPriceUpdate(USDC, true);
    }

    function testSetBlockAssetPriceAndUpdateByUsual() public {
        testSetBlockAssetPrice();
        vm.prank(admin);
        dataPublisher.publishData(USDC, 1.01e18);
        (, int256 answer,,) = dataPublisher.latestRoundData(USDC);
        assertEq(answer, 1.01e18, "Price should be 1.01");
    }

    function testSetBlockAssetPriceAndPublishAfterRemove() public {
        testSetBlockAssetPriceAndUpdateByUsual();
        vm.prank(admin);
        dataPublisher.blockAssetPriceUpdate(USDC, false);
        vm.prank(hashnote);
        dataPublisher.publishData(USDC, 1.005e18);
        (, int256 answer,,) = dataPublisher.latestRoundData(USDC);
        assertEq(answer, 1.005e18, "Price should be 1.005");
    }
}
