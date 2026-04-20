// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/BatchAuction.sol";
import "../src/OrderBook.sol";
import "../src/Vault.sol";
import "../src/FeeModel.sol";
import "../src/OutcomeToken.sol";
import "../src/ITypes.sol";
import "./mocks/MockUSDT.sol";

contract OrderBookAmendTest is Test {
    struct ExpectedOrderAmended {
        uint256 orderId;
        uint256 marketId;
        address owner;
        uint256 oldTick;
        uint256 newTick;
        uint256 oldLots;
        uint256 newLots;
        uint256 oldFeeBps;
        uint256 newFeeBps;
        uint256 oldBatchId;
        uint256 newBatchId;
        bool wasResting;
        bool isResting;
    }

    event OrderAmended(
        uint256 indexed orderId,
        uint256 indexed marketId,
        address indexed owner,
        uint256 oldTick,
        uint256 newTick,
        uint256 oldLots,
        uint256 newLots,
        uint256 oldFeeBps,
        uint256 newFeeBps,
        uint256 oldBatchId,
        uint256 newBatchId,
        bool wasResting,
        bool isResting
    );

    BatchAuction public auction;
    OrderBook public book;
    Vault public vault;
    FeeModel public feeModel;
    OutcomeToken public token;
    MockUSDT public usdt;

    address public admin = address(0x1);
    address public operator = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public user3 = address(0x5);
    address public feeCollector = address(0x99);

    uint256 public constant LOT = 1e16;

    function setUp() public {
        usdt = new MockUSDT();

        vm.startPrank(admin);
        vault = new Vault(admin, address(usdt));
        feeModel = new FeeModel(admin, 20, feeCollector);
        token = new OutcomeToken(admin);
        book = new OrderBook(admin, address(vault), address(feeModel), address(token));
        auction = new BatchAuction(admin, address(book), address(vault), address(token));

        book.grantRole(book.OPERATOR_ROLE(), operator);
        book.grantRole(book.OPERATOR_ROLE(), address(auction));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(book));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(auction));
        token.grantRole(token.MINTER_ROLE(), address(auction));
        token.grantRole(token.ESCROW_ROLE(), address(auction));
        vm.stopPrank();

        address[3] memory users = [user1, user2, user3];
        for (uint256 i = 0; i < users.length; i++) {
            usdt.mint(users[i], 100000 ether);
            vm.prank(users[i]);
            usdt.approve(address(vault), type(uint256).max);
        }
    }

    function _setupMarket() internal returns (uint256) {
        vm.prank(operator);
        return book.registerMarket(1, 3, block.timestamp + 3600, false);
    }

    function _setupMarketWithClearing() internal returns (uint256 mId) {
        mId = _setupMarket();
        vm.prank(user1);
        book.placeOrder(mId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);
        auction.clearBatch(mId);
    }

    function _requiredLocked(Side side, uint256 tick, uint256 lots) internal view returns (uint256) {
        uint256 collateral = side == Side.Bid ? (lots * LOT * tick) / 100 : (lots * LOT * (100 - tick)) / 100;
        return collateral + feeModel.calculateFee(collateral);
    }

    function _amend(uint256 marketId, uint256 orderId, uint8 newTick, uint64 newLots, address user) internal {
        AmendOrderParam[] memory params = new AmendOrderParam[](1);
        params[0] = AmendOrderParam(orderId, newTick, newLots);
        vm.prank(user);
        book.amendOrders(marketId, params);
    }

    function _currentBatchId(uint256 marketId) internal view returns (uint32 batchId) {
        (, , , batchId, , , , ) = book.markets(marketId);
    }

    function _fillCurrentBatchTo(uint256 marketId, uint256 targetLength) internal {
        uint32 batchId = _currentBatchId(marketId);
        uint256 placed = book.getBatchOrderIds(marketId, batchId).length;

        for (uint256 u = 0; placed < targetLength; u++) {
            address filler = address(uint160(0xF000 + u));
            usdt.mint(filler, 100000 ether);
            vm.prank(filler);
            usdt.approve(address(vault), type(uint256).max);

            uint256 count = targetLength - placed > 20 ? 20 : targetLength - placed;
            vm.startPrank(filler);
            for (uint256 j = 0; j < count; j++) {
                book.placeOrder(marketId, Side.Bid, OrderType.GoodTilCancel, 50, 1);
            }
            vm.stopPrank();

            placed += count;
        }
    }

    function _expectOrderAmended(ExpectedOrderAmended memory expected) internal {
        vm.expectEmit(true, true, true, true, address(book));
        emit OrderAmended(
            expected.orderId,
            expected.marketId,
            expected.owner,
            expected.oldTick,
            expected.newTick,
            expected.oldLots,
            expected.newLots,
            expected.oldFeeBps,
            expected.newFeeBps,
            expected.oldBatchId,
            expected.newBatchId,
            expected.wasResting,
            expected.isResting
        );
    }

    function test_AmendOrders_ActiveBuyOrderInPlace() public {
        uint256 mId = _setupMarketWithClearing();

        vm.prank(user1);
        uint256 orderId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 45, 10);
        uint256 activeCountBefore = book.activeOrderCount(user1, mId);

        _amend(mId, orderId, 48, 12, user1);

        (, Side side, OrderType orderType, uint8 tick, uint64 lots, uint64 id,,,, uint16 feeBps) = book.orders(orderId);
        assertEq(id, orderId, "order id should stay stable");
        assertEq(uint8(side), uint8(Side.Bid));
        assertEq(uint8(orderType), uint8(OrderType.GoodTilCancel));
        assertEq(tick, 48, "tick should update in place");
        assertEq(lots, 12, "lots should update in place");
        assertEq(book.bidVolumeAt(mId, 45), 0, "old tree volume removed");
        assertEq(book.bidVolumeAt(mId, 48), 12, "new tree volume added");
        assertFalse(book.isResting(orderId), "active amend should stay active");
        assertEq(book.activeOrderCount(user1, mId), activeCountBefore, "active count should be unchanged");
        assertEq(feeBps, feeModel.feeBps(), "fee bps should refresh on amend");
    }

    function test_AmendOrders_EmitsEventForActiveReprice() public {
        uint256 mId = _setupMarketWithClearing();

        vm.prank(user1);
        uint256 orderId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 45, 10);
        (, , , uint8 oldTick, uint64 oldLots, , , uint32 oldBatchId, , uint16 oldFeeBps) = book.orders(orderId);

        vm.prank(admin);
        feeModel.setFeeBps(35);

        AmendOrderParam[] memory params = new AmendOrderParam[](1);
        params[0] = AmendOrderParam(orderId, 48, 12);
        ExpectedOrderAmended memory expected;
        expected.orderId = orderId;
        expected.marketId = mId;
        expected.owner = user1;
        expected.oldTick = oldTick;
        expected.newTick = 48;
        expected.oldLots = oldLots;
        expected.newLots = 12;
        expected.oldFeeBps = oldFeeBps;
        expected.newFeeBps = 35;
        expected.oldBatchId = oldBatchId;
        expected.newBatchId = oldBatchId;
        _expectOrderAmended(expected);

        vm.prank(user1);
        book.amendOrders(mId, params);
    }

    function test_AmendOrders_RestingBuyOrderInPlace() public {
        uint256 mId = _setupMarketWithClearing();

        vm.prank(user1);
        uint256 orderId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 5, 1);
        assertTrue(book.isResting(orderId), "order starts resting");
        assertEq(book.restingIndexPlusOne(orderId), 1, "resting index tracked");

        _amend(mId, orderId, 6, 2, user1);

        (,,, uint8 tick, uint64 lots, uint64 id,,,,) = book.orders(orderId);
        uint256[] memory restingIds = book.getRestingOrderIds(mId);
        assertEq(id, orderId, "resting amend should preserve id");
        assertEq(tick, 6, "resting amend updates tick");
        assertEq(lots, 2, "resting amend updates lots");
        assertTrue(book.isResting(orderId), "order should remain resting");
        assertEq(restingIds.length, 1, "resting list should not duplicate entries");
        assertEq(restingIds[0], orderId, "resting list should still contain the same order");
        assertEq(book.restingIndexPlusOne(orderId), 1, "resting index should remain valid");
        assertEq(book.bidVolumeAt(mId, 6), 0, "resting order should not enter tree");
    }

    function test_AmendOrders_RestingToActive() public {
        uint256 mId = _setupMarketWithClearing();

        vm.prank(user1);
        uint256 orderId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 5, 1);
        assertTrue(book.isResting(orderId), "order starts resting");

        _amend(mId, orderId, 30, 2, user1);

        (,,, uint8 tick, uint64 lots,,, uint32 batchId,,) = book.orders(orderId);
        uint256[] memory batchIds = book.getBatchOrderIds(mId, batchId);

        assertFalse(book.isResting(orderId), "order should activate");
        assertEq(book.restingIndexPlusOne(orderId), 0, "resting index should clear");
        assertEq(tick, 30, "tick should update");
        assertEq(lots, 2, "lots should update");
        assertEq(book.bidVolumeAt(mId, 30), 2, "activated order should be added to the tree");
        assertEq(batchIds[batchIds.length - 1], orderId, "activated order should join the current batch");
    }

    function test_AmendOrders_EmitsEventForRestingToActive() public {
        uint256 mId = _setupMarketWithClearing();
        uint32 currentBatchId = _currentBatchId(mId);

        vm.prank(user1);
        uint256 orderId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 5, 1);
        (, , , uint8 oldTick, uint64 oldLots, , , uint32 oldBatchId, , uint16 oldFeeBps) = book.orders(orderId);

        AmendOrderParam[] memory params = new AmendOrderParam[](1);
        params[0] = AmendOrderParam(orderId, 30, 2);
        ExpectedOrderAmended memory expected;
        expected.orderId = orderId;
        expected.marketId = mId;
        expected.owner = user1;
        expected.oldTick = oldTick;
        expected.newTick = 30;
        expected.oldLots = oldLots;
        expected.newLots = 2;
        expected.oldFeeBps = oldFeeBps;
        expected.newFeeBps = oldFeeBps;
        expected.oldBatchId = oldBatchId;
        expected.newBatchId = currentBatchId;
        expected.wasResting = true;
        _expectOrderAmended(expected);

        vm.prank(user1);
        book.amendOrders(mId, params);
    }

    function test_AmendOrders_RestingToActive_UsesCurrentOrNextBatchWhenNearFull() public {
        uint256 mId = _setupMarketWithClearing();
        uint32 currentBatchId = _currentBatchId(mId);

        vm.startPrank(user1);
        uint256 currentBatchOrder = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 5, 1);
        uint256 overflowOrder = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 6, 1);
        vm.stopPrank();

        _fillCurrentBatchTo(mId, book.MAX_ORDERS_PER_BATCH() - 1);

        _amend(mId, currentBatchOrder, 30, 2, user1);

        (, , , , , , , uint32 firstBatchId, , ) = book.orders(currentBatchOrder);
        uint256[] memory currentBatchIds = book.getBatchOrderIds(mId, currentBatchId);
        assertEq(firstBatchId, currentBatchId, "near-full current batch should still accept one amend");
        assertEq(currentBatchIds.length, book.MAX_ORDERS_PER_BATCH(), "current batch should become full");
        assertEq(currentBatchIds[currentBatchIds.length - 1], currentBatchOrder, "current batch should append amend");

        _amend(mId, overflowOrder, 31, 3, user1);

        (,,, uint8 tick, uint64 lots,,, uint32 secondBatchId,,) = book.orders(overflowOrder);
        uint256[] memory nextBatchIds = book.getBatchOrderIds(mId, currentBatchId + 1);

        assertFalse(book.isResting(overflowOrder), "overflow amend should activate order");
        assertEq(book.restingIndexPlusOne(overflowOrder), 0, "overflow amend should clear resting index");
        assertEq(tick, 31, "overflow amend should update tick");
        assertEq(lots, 3, "overflow amend should update lots");
        assertEq(secondBatchId, currentBatchId + 1, "full current batch should spill amend to next batch");
        assertEq(nextBatchIds.length, 1, "next batch should receive the overflow amend");
        assertEq(nextBatchIds[0], overflowOrder, "overflow amend should be queued in next batch");
        assertEq(book.bidVolumeAt(mId, 31), 3, "overflow amend should enter active tree volume");
    }

    function test_AmendOrders_RejectsActiveToResting() public {
        uint256 mId = _setupMarketWithClearing();

        vm.prank(user1);
        uint256 orderId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 45, 1);

        AmendOrderParam[] memory params = new AmendOrderParam[](1);
        params[0] = AmendOrderParam(orderId, 5, 1);

        vm.expectRevert("OrderBook: amend would rest");
        vm.prank(user1);
        book.amendOrders(mId, params);
    }

    function test_AmendOrders_UsesVaultBalanceForRequotes() public {
        uint256 mId = _setupMarketWithClearing();

        vm.prank(user1);
        uint256 orderId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 50, 10);

        uint256 walletBefore = usdt.balanceOf(user1);
        uint256 oldRequired = _requiredLocked(Side.Bid, 50, 10);
        uint256 downRequired = _requiredLocked(Side.Bid, 40, 5);

        _amend(mId, orderId, 40, 5, user1);

        assertEq(usdt.balanceOf(user1), walletBefore, "amend-down should not withdraw to wallet");
        assertEq(vault.locked(user1), downRequired, "locked balance should decrease");
        assertEq(vault.available(user1), oldRequired - downRequired, "excess should stay available in vault");

        uint256 upRequired = _requiredLocked(Side.Bid, 42, 8);
        _amend(mId, orderId, 42, 8, user1);

        assertEq(usdt.balanceOf(user1), walletBefore, "amend-up should reuse vault balance before wallet");
        assertEq(vault.locked(user1), upRequired, "locked balance should reflect the latest quote");
        assertEq(
            vault.available(user1), oldRequired - upRequired, "available balance should shrink by the reused amount"
        );
    }

    function test_AmendOrders_ClearBatchSettlesAmendedOrder() public {
        uint256 mId = _setupMarketWithClearing();
        uint256 yesBefore = token.balanceOf(user1, token.yesTokenId(mId));

        vm.prank(user1);
        uint256 orderId = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 45, 10);

        _amend(mId, orderId, 50, 10, user1);

        vm.prank(user2);
        book.placeOrder(mId, Side.Ask, OrderType.GoodTilBatch, 50, 10);
        auction.clearBatch(mId);

        (,,,, uint64 lotsAfter, uint64 id,,,,) = book.orders(orderId);
        assertEq(id, orderId, "settled order id should remain the same");
        assertEq(lotsAfter, 0, "amended order should settle normally");
        assertEq(token.balanceOf(user1, token.yesTokenId(mId)) - yesBefore, 10, "buyer should receive YES tokens");
    }

    function _seedLadder(uint256 mId, address user) internal returns (uint256[] memory orderIds) {
        orderIds = new uint256[](4);
        vm.startPrank(user);
        orderIds[0] = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 45, 10);
        orderIds[1] = book.placeOrder(mId, Side.Bid, OrderType.GoodTilCancel, 48, 8);
        orderIds[2] = book.placeOrder(mId, Side.Ask, OrderType.GoodTilCancel, 55, 10);
        orderIds[3] = book.placeOrder(mId, Side.Ask, OrderType.GoodTilCancel, 58, 8);
        vm.stopPrank();
    }

    function test_AmendOrders_GasComparison_4LegLadder() public {
        uint256 replaceMarket = _setupMarketWithClearing();
        uint256 amendMarket = _setupMarketWithClearing();

        uint256[] memory replaceIds = _seedLadder(replaceMarket, user1);
        uint256[] memory amendIds = _seedLadder(amendMarket, user2);

        OrderParam[] memory replaceParams = new OrderParam[](4);
        replaceParams[0] = OrderParam(Side.Bid, OrderType.GoodTilCancel, 46, 10);
        replaceParams[1] = OrderParam(Side.Bid, OrderType.GoodTilCancel, 49, 8);
        replaceParams[2] = OrderParam(Side.Ask, OrderType.GoodTilCancel, 54, 10);
        replaceParams[3] = OrderParam(Side.Ask, OrderType.GoodTilCancel, 57, 8);

        AmendOrderParam[] memory amendParams = new AmendOrderParam[](4);
        amendParams[0] = AmendOrderParam(amendIds[0], 46, 10);
        amendParams[1] = AmendOrderParam(amendIds[1], 49, 8);
        amendParams[2] = AmendOrderParam(amendIds[2], 54, 10);
        amendParams[3] = AmendOrderParam(amendIds[3], 57, 8);

        uint256 replaceGasStart = gasleft();
        vm.prank(user1);
        book.replaceOrders(replaceIds, replaceMarket, replaceParams);
        uint256 replaceGas = replaceGasStart - gasleft();

        uint256 amendGasStart = gasleft();
        vm.prank(user2);
        book.amendOrders(amendMarket, amendParams);
        uint256 amendGas = amendGasStart - gasleft();

        emit log_named_uint("replaceOrders 4-leg gas", replaceGas);
        emit log_named_uint("amendOrders 4-leg gas", amendGas);
        assertLt(amendGas, replaceGas, "amendOrders should be cheaper than replaceOrders");
    }
}
