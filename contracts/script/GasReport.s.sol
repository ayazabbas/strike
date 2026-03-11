// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/Vault.sol";
import "../src/OrderBook.sol";
import "../src/BatchAuction.sol";
import "../src/MarketFactory.sol";
import "../src/PythResolver.sol";
import "../src/Redemption.sol";
import "../src/OutcomeToken.sol";
import "../src/ITypes.sol";

/// @title GasReport
/// @notice Measures gas for every user-facing + keeper function on devnet.
contract GasReport is Script {
    // Anvil default addresses (from Deploy.s.sol output)
    address constant VAULT_ADDR = 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9;
    address constant ORDERBOOK_ADDR = 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9;
    address constant BATCH_ADDR = 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707;
    address payable constant FACTORY_ADDR = payable(0xa513E6E4b8f2a923D98304ec87F64353C4D5C853);
    address constant RESOLVER_ADDR = 0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6;
    address constant REDEMPTION_ADDR = 0x0165878A594ca255338adfa4d48449f69242Eb8F;
    address constant OUTCOME_ADDR = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;

    // Anvil accounts
    uint256 constant DEPLOYER_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant TRADER_A_PK = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 constant TRADER_B_PK = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    address deployer;
    address traderA;
    address traderB;

    Vault vault;
    OrderBook orderBook;
    BatchAuction batch;
    MarketFactory factory;

    struct GasResult {
        string name;
        uint256 gas;
    }

    GasResult[] results;

    function _record(string memory name, uint256 gasBefore) internal {
        uint256 used = gasBefore - gasleft();
        results.push(GasResult(name, used));
        console.log("[GAS] %s: %d", name, used);
    }

    function run() external {
        deployer = vm.addr(DEPLOYER_PK);
        traderA = vm.addr(TRADER_A_PK);
        traderB = vm.addr(TRADER_B_PK);

        vault = Vault(payable(VAULT_ADDR));
        orderBook = OrderBook(ORDERBOOK_ADDR);
        batch = BatchAuction(BATCH_ADDR);
        factory = MarketFactory(FACTORY_ADDR);

        console.log("=== Strike Gas Report ===");
        console.log("Chain ID: %d", block.chainid);
        console.log("");

        // --- 1. Vault deposit ---
        vm.startBroadcast(TRADER_A_PK);
        uint256 g = gasleft();
        vault.deposit{value: 5 ether}();
        _record("Vault.deposit (first)", g);
        vm.stopBroadcast();

        vm.startBroadcast(TRADER_B_PK);
        g = gasleft();
        vault.deposit{value: 5 ether}();
        _record("Vault.deposit (subsequent)", g);
        vm.stopBroadcast();

        // --- 2. Create market ---
        vm.startBroadcast(DEPLOYER_PK);
        g = gasleft();
        uint256 marketId = factory.createMarket(
            0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace, // BTC/USD
            50000_00000000, // strike price ($50k, expo=-8)
            3600,         // duration (1hr)
            60,           // batchInterval
            1             // minLots
        );
        _record("MarketFactory.createMarket", g);
        vm.stopBroadcast();

        // --- 3. Place orders ---
        // Trader A: BID at tick 60, 10 lots
        vm.startBroadcast(TRADER_A_PK);
        g = gasleft();
        orderBook.placeOrder(marketId, Side.Bid, OrderType.GoodTilCancel, 60, 10);
        _record("OrderBook.placeOrder (BID, first in market)", g);

        // Second bid at different tick
        g = gasleft();
        orderBook.placeOrder(marketId, Side.Bid, OrderType.GoodTilCancel, 55, 20);
        _record("OrderBook.placeOrder (BID, second)", g);

        // GTB order
        g = gasleft();
        orderBook.placeOrder(marketId, Side.Bid, OrderType.GoodTilBatch, 50, 5);
        _record("OrderBook.placeOrder (BID, GTB)", g);
        vm.stopBroadcast();

        // Trader B: ASK at tick 60, 10 lots (crosses with bid)
        vm.startBroadcast(TRADER_B_PK);
        g = gasleft();
        orderBook.placeOrder(marketId, Side.Ask, OrderType.GoodTilCancel, 60, 10);
        _record("OrderBook.placeOrder (ASK, crossing)", g);

        g = gasleft();
        orderBook.placeOrder(marketId, Side.Ask, OrderType.GoodTilCancel, 65, 15);
        _record("OrderBook.placeOrder (ASK, non-crossing)", g);
        vm.stopBroadcast();

        // --- 4. Cancel order ---
        vm.startBroadcast(TRADER_B_PK);
        g = gasleft();
        orderBook.cancelOrder(5); // cancel the non-crossing ask (orderId 5)
        _record("OrderBook.cancelOrder", g);
        vm.stopBroadcast();

        // --- 5. Clear batch ---
        // Advance time past batch interval
        vm.warp(block.timestamp + 61);

        vm.startBroadcast(DEPLOYER_PK);
        g = gasleft();
        batch.clearBatch(marketId);
        _record("BatchAuction.clearBatch (2 crossing orders)", g);
        vm.stopBroadcast();

        // --- 6. Claim fills ---
        vm.startBroadcast(TRADER_A_PK);
        g = gasleft();
        batch.claimFills(1); // order 1: BID at tick 60
        _record("BatchAuction.claimFills (full fill, GTC)", g);
        vm.stopBroadcast();

        vm.startBroadcast(TRADER_B_PK);
        g = gasleft();
        batch.claimFills(4); // order 4: ASK at tick 60
        _record("BatchAuction.claimFills (full fill, ASK)", g);
        vm.stopBroadcast();

        // --- 7. Prune expired GTB order ---
        // Advance another batch
        vm.warp(block.timestamp + 61);
        vm.startBroadcast(DEPLOYER_PK);
        batch.clearBatch(marketId); // clear batch 2
        vm.stopBroadcast();

        vm.startBroadcast(DEPLOYER_PK);
        g = gasleft();
        batch.pruneExpiredOrder(3); // GTB order from trader A
        _record("BatchAuction.pruneExpiredOrder", g);
        vm.stopBroadcast();

        // --- 8. Vault withdraw ---
        vm.startBroadcast(TRADER_A_PK);
        g = gasleft();
        vault.withdraw(0.5 ether);
        _record("Vault.withdraw", g);
        vm.stopBroadcast();

        // --- Summary ---
        console.log("");
        console.log("=== Summary (BNB Chain @ 1 gwei gas price) ===");
        console.log("%-45s %10s %12s", "Function", "Gas", "Cost (BNB)");
        console.log("-----------------------------------------------------------");
        for (uint256 i = 0; i < results.length; i++) {
            // Cost at 1 gwei = gas * 1e-9 BNB
            // We show in units of 1e-6 BNB for readability
            uint256 microBnb = results[i].gas / 1000; // gas * 1e-9 * 1e6 = gas / 1000
            console.log(results[i].name);
            console.log("  gas: %d  |  ~%d microBNB @ 1gwei", results[i].gas, microBnb);
        }
    }
}
