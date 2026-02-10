// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {Market} from "../src/Market.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {MockPyth} from "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";

contract MarketFactoryTest is Test {
    MockPyth public mockPyth;
    MarketFactory public factory;

    address public owner = address(this);
    address public feeCollector = makeAddr("feeCollector");
    address public alice = makeAddr("alice");

    bytes32 public constant BTC_PRICE_ID = bytes32(uint256(1));
    bytes32 public constant BNB_PRICE_ID = bytes32(uint256(2));
    int64 public constant BTC_PRICE = 100_000 * 1e8;
    int64 public constant BNB_PRICE = 600 * 1e8;
    int32 public constant EXPO = -8;
    uint64 public constant CONF = 50 * 1e8;

    function setUp() public {
        mockPyth = new MockPyth(60, 1);
        factory = new MarketFactory(address(mockPyth), feeCollector);
        vm.deal(alice, 100 ether);
    }

    function _createPriceUpdate(bytes32 id, int64 price) internal view returns (bytes[] memory) {
        bytes[] memory updateData = new bytes[](1);
        updateData[0] = mockPyth.createPriceFeedUpdateData(
            id, price, CONF, EXPO, price, CONF,
            uint64(block.timestamp), uint64(block.timestamp) - 1
        );
        return updateData;
    }

    // ─── Creation Tests ──────────────────────────────────────────────────

    function test_createMarket() public {
        bytes[] memory updateData = _createPriceUpdate(BTC_PRICE_ID, BTC_PRICE);
        uint256 fee = mockPyth.getUpdateFee(updateData);

        address marketAddr = factory.createMarket{value: fee}(
            BTC_PRICE_ID, 1 hours, updateData
        );

        assertTrue(marketAddr != address(0));
        assertTrue(factory.isMarket(marketAddr));
        assertEq(factory.getMarketCount(), 1);

        Market m = Market(payable(marketAddr));
        assertEq(m.strikePrice(), BTC_PRICE);
        assertEq(uint256(m.state()), uint256(Market.State.Open));
    }

    function test_createMultipleMarkets() public {
        // BTC market
        bytes[] memory btcUpdate = _createPriceUpdate(BTC_PRICE_ID, BTC_PRICE);
        uint256 fee = mockPyth.getUpdateFee(btcUpdate);
        factory.createMarket{value: fee}(BTC_PRICE_ID, 1 hours, btcUpdate);

        // BNB market
        bytes[] memory bnbUpdate = _createPriceUpdate(BNB_PRICE_ID, BNB_PRICE);
        fee = mockPyth.getUpdateFee(bnbUpdate);
        factory.createMarket{value: fee}(BNB_PRICE_ID, 4 hours, bnbUpdate);

        assertEq(factory.getMarketCount(), 2);
    }

    function test_createMarketEmitsEvent() public {
        bytes[] memory updateData = _createPriceUpdate(BTC_PRICE_ID, BTC_PRICE);
        uint256 fee = mockPyth.getUpdateFee(updateData);

        // We can't predict the exact market address, so just check indexed params
        vm.expectEmit(false, true, false, false);
        emit MarketFactory.MarketCreated(address(0), BTC_PRICE_ID, 0, 0);

        factory.createMarket{value: fee}(BTC_PRICE_ID, 1 hours, updateData);
    }

    function test_revertDurationTooShort() public {
        bytes[] memory updateData = _createPriceUpdate(BTC_PRICE_ID, BTC_PRICE);
        uint256 fee = mockPyth.getUpdateFee(updateData);

        vm.expectRevert("Duration too short");
        factory.createMarket{value: fee}(BTC_PRICE_ID, 100, updateData);
    }

    function test_revertDurationTooLong() public {
        bytes[] memory updateData = _createPriceUpdate(BTC_PRICE_ID, BTC_PRICE);
        uint256 fee = mockPyth.getUpdateFee(updateData);

        vm.expectRevert("Duration too long");
        factory.createMarket{value: fee}(BTC_PRICE_ID, 8 days, updateData);
    }

    // ─── Registry Tests ──────────────────────────────────────────────────

    function test_getMarketsPagination() public {
        // Create 3 markets
        for (uint256 i = 0; i < 3; i++) {
            bytes[] memory updateData = _createPriceUpdate(BTC_PRICE_ID, BTC_PRICE);
            uint256 fee = mockPyth.getUpdateFee(updateData);
            factory.createMarket{value: fee}(BTC_PRICE_ID, 1 hours, updateData);
        }

        // Get first 2
        address[] memory page1 = factory.getMarkets(0, 2);
        assertEq(page1.length, 2);

        // Get remaining
        address[] memory page2 = factory.getMarkets(2, 10);
        assertEq(page2.length, 1);

        // Out of bounds
        address[] memory empty = factory.getMarkets(10, 5);
        assertEq(empty.length, 0);
    }

    // ─── Admin Tests ─────────────────────────────────────────────────────

    function test_setFeeCollector() public {
        address newCollector = makeAddr("newCollector");
        factory.setFeeCollector(newCollector);
        assertEq(factory.feeCollector(), newCollector);
    }

    function test_revertSetFeeCollectorZero() public {
        vm.expectRevert("Invalid address");
        factory.setFeeCollector(address(0));
    }

    function test_revertNonOwnerSetFeeCollector() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.setFeeCollector(alice);
    }

    function test_revertNonOwnerPauseMarket() public {
        bytes[] memory updateData = _createPriceUpdate(BTC_PRICE_ID, BTC_PRICE);
        uint256 fee = mockPyth.getUpdateFee(updateData);
        address marketAddr = factory.createMarket{value: fee}(BTC_PRICE_ID, 1 hours, updateData);

        vm.prank(alice);
        vm.expectRevert();
        factory.pauseMarket(marketAddr);
    }

    function test_revertPauseNonMarket() public {
        vm.expectRevert("Not a market");
        factory.pauseMarket(makeAddr("fake"));
    }

    // ─── Constructor Tests ───────────────────────────────────────────────

    function test_revertZeroPythAddress() public {
        vm.expectRevert("Invalid Pyth address");
        new MarketFactory(address(0), feeCollector);
    }

    function test_revertZeroFeeCollector() public {
        vm.expectRevert("Invalid fee collector");
        new MarketFactory(address(mockPyth), address(0));
    }

    function test_implementationDeployed() public view {
        assertTrue(factory.marketImplementation() != address(0));
    }
}
