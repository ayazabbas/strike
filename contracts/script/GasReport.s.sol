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
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title GasReport
/// @notice Measures gas for every user-facing + keeper function on devnet.
///         Run after Deploy.s.sol on a local anvil node.
contract GasReport is Script {
    // Anvil default addresses (from Deploy.s.sol output — update after deploy)
    address constant USDT_ADDR = address(0);        // fill after deploy
    address constant VAULT_ADDR = address(0);       // fill after deploy
    address constant ORDERBOOK_ADDR = address(0);   // fill after deploy
    address constant BATCH_ADDR = address(0);       // fill after deploy
    address constant FACTORY_ADDR = address(0);     // fill after deploy

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

        vault = Vault(VAULT_ADDR);
        orderBook = OrderBook(ORDERBOOK_ADDR);
        batch = BatchAuction(BATCH_ADDR);
        factory = MarketFactory(FACTORY_ADDR);

        IERC20 usdt = IERC20(USDT_ADDR);

        console.log("=== Strike Gas Report ===");
        console.log("Chain ID: %d", block.chainid);
        console.log("");
        console.log("NOTE: Update addresses after running Deploy.s.sol");

        // --- 1. Approve + PlaceOrder covers deposit ---
        vm.startBroadcast(TRADER_A_PK);
        usdt.approve(address(vault), type(uint256).max);
        vm.stopBroadcast();

        vm.startBroadcast(TRADER_B_PK);
        usdt.approve(address(vault), type(uint256).max);
        vm.stopBroadcast();

        // --- 2. Create market ---
        vm.startBroadcast(DEPLOYER_PK);
        uint256 g = gasleft();
        uint256 marketId = factory.createMarket(
            0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace,
            50000_00000000,
            3600,
            60,
            1
        );
        _record("MarketFactory.createMarket", g);
        vm.stopBroadcast();

        // --- 3. Place orders ---
        vm.startBroadcast(TRADER_A_PK);
        g = gasleft();
        orderBook.placeOrder(marketId, Side.Bid, OrderType.GoodTilCancel, 60, 10);
        _record("OrderBook.placeOrder (BID, first)", g);
        vm.stopBroadcast();

        vm.startBroadcast(TRADER_B_PK);
        g = gasleft();
        orderBook.placeOrder(marketId, Side.Ask, OrderType.GoodTilCancel, 60, 10);
        _record("OrderBook.placeOrder (ASK, crossing)", g);
        vm.stopBroadcast();

        // --- 4. Clear batch (atomic settlement) ---
        vm.warp(block.timestamp + 61);

        vm.startBroadcast(DEPLOYER_PK);
        g = gasleft();
        batch.clearBatch(marketId);
        _record("BatchAuction.clearBatch (2 orders)", g);
        vm.stopBroadcast();

        // --- Summary ---
        console.log("");
        console.log("=== Summary ===");
        for (uint256 i = 0; i < results.length; i++) {
            console.log(results[i].name);
            console.log("  gas: %d", results[i].gas);
        }
    }
}
