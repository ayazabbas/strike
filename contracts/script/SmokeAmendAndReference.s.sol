// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {OrderBook} from "../src/OrderBook.sol";
import {Vault} from "../src/Vault.sol";
import {BatchAuction} from "../src/BatchAuction.sol";
import {Side, OrderType, AmendOrderParam} from "../src/ITypes.sol";
import {MockUSDT} from "../test/mocks/MockUSDT.sol";

contract SmokeAmendAndReferenceScript is Script {
    bytes32 internal constant BTC_USD_PRICE_ID =
        0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;

    uint256 internal constant USER1_KEY =
        0x1111111111111111111111111111111111111111111111111111111111111111;
    uint256 internal constant USER2_KEY =
        0x2222222222222222222222222222222222222222222222222222222222222222;
    uint256 internal constant USER3_KEY =
        0x3333333333333333333333333333333333333333333333333333333333333333;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        MarketFactory factory = MarketFactory(vm.envAddress("MARKET_FACTORY_ADDR"));
        OrderBook book = OrderBook(vm.envAddress("ORDER_BOOK_ADDR"));
        Vault vault = Vault(vm.envAddress("VAULT_ADDR"));
        BatchAuction auction = BatchAuction(vm.envAddress("BATCH_AUCTION_ADDR"));
        MockUSDT usdt = MockUSDT(vm.envAddress("USDT_ADDR"));

        address deployer = vm.addr(deployerKey);
        address user1 = vm.addr(USER1_KEY);
        address user2 = vm.addr(USER2_KEY);
        address user3 = vm.addr(USER3_KEY);

        console.log("Deployer:", deployer);
        console.log("User1:", user1);
        console.log("User2:", user2);
        console.log("User3:", user3);

        vm.startBroadcast(deployerKey);
        _sendBnB(user1, 0.01 ether);
        _sendBnB(user2, 0.01 ether);
        _sendBnB(user3, 0.01 ether);
        usdt.mint(user1, 100000 ether);
        usdt.mint(user2, 100000 ether);
        usdt.mint(user3, 100000 ether);
        uint256 factoryMarketId = factory.nextFactoryMarketId();
        factory.createMarket(BTC_USD_PRICE_ID, 5_000_000_000_000, block.timestamp + 2 hours, 60, 1);
        vm.stopBroadcast();

        (,,,,,,,uint256 marketId,,) = factory.marketMeta(factoryMarketId);
        require(marketId != 0, "market not created");
        console.log("Factory market ID:", factoryMarketId);
        console.log("OrderBook market ID:", marketId);

        vm.startBroadcast(USER1_KEY);
        usdt.approve(address(vault), type(uint256).max);
        uint256 anchorBid = book.placeOrder(marketId, Side.Bid, OrderType.GoodTilBatch, 50, 10);
        vm.stopBroadcast();

        vm.startBroadcast(USER2_KEY);
        usdt.approve(address(vault), type(uint256).max);
        uint256 anchorAsk = book.placeOrder(marketId, Side.Ask, OrderType.GoodTilBatch, 50, 10);
        vm.stopBroadcast();

        console.log("Anchor bid order:", anchorBid);
        console.log("Anchor ask order:", anchorAsk);

        vm.startBroadcast(deployerKey);
        auction.clearBatch(marketId);
        vm.stopBroadcast();

        require(book.lastClearingTick(marketId) == 50, "expected stale clearing tick anchor");

        vm.startBroadcast(USER1_KEY);
        uint256 activeBid = book.placeOrder(marketId, Side.Bid, OrderType.GoodTilCancel, 30, 5);
        vm.stopBroadcast();

        vm.startBroadcast(USER2_KEY);
        uint256 activeAsk = book.placeOrder(marketId, Side.Ask, OrderType.GoodTilCancel, 35, 5);
        vm.stopBroadcast();

        console.log("Active bid order:", activeBid);
        console.log("Active ask order:", activeAsk);

        uint256 ref = book.currentReferenceTick(marketId);
        console.log("Current reference tick:", ref);
        require(ref == 32, "live midpoint should override stale lastClearingTick");

        vm.startBroadcast(USER3_KEY);
        usdt.approve(address(vault), type(uint256).max);
        uint256 nearbyBid = book.placeOrder(marketId, Side.Bid, OrderType.GoodTilCancel, 25, 1);
        vm.stopBroadcast();

        require(!book.isResting(nearbyBid), "nearby bid should stay active under live reference");
        require(book.bidVolumeAt(marketId, 25) == 1, "nearby bid should be active in tree");
        console.log("Nearby active bid order:", nearbyBid);

        AmendOrderParam[] memory params = new AmendOrderParam[](1);
        params[0] = AmendOrderParam(nearbyBid, 27, 2);

        vm.startBroadcast(USER3_KEY);
        book.amendOrders(marketId, params);
        vm.stopBroadcast();

        (, Side side, OrderType orderType, uint8 tick, uint64 lots, uint64 storedId,,,,) = book.orders(nearbyBid);
        require(uint8(side) == uint8(Side.Bid), "amended order side mismatch");
        require(uint8(orderType) == uint8(OrderType.GoodTilCancel), "amended order type mismatch");
        require(storedId == nearbyBid, "order id should remain stable after amend");
        require(tick == 27, "amended tick mismatch");
        require(lots == 2, "amended lots mismatch");
        require(!book.isResting(nearbyBid), "amended order should remain active");
        require(book.bidVolumeAt(marketId, 25) == 0, "old active tree volume should be removed");
        require(book.bidVolumeAt(marketId, 27) == 2, "new active tree volume should be inserted");

        console.log("Smoke passed: stale clearing tick fix + amendOrders verified live.");
    }

    function _sendBnB(address to, uint256 amount) internal {
        (bool ok,) = payable(to).call{value: amount}("");
        require(ok, "bnb transfer failed");
    }
}
