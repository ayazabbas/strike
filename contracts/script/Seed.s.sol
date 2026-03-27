// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {Vault} from "../src/Vault.sol";
import {OrderBook} from "../src/OrderBook.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {Side, OrderType} from "../src/ITypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Seed the devnet with test orders that cross, giving the
///         batch-keeper something real to clear.
contract SeedScript is Script {
    function run() external {
        Vault vault = Vault(vm.envAddress("VAULT_ADDR"));
        OrderBook orderBook = OrderBook(vm.envAddress("ORDER_BOOK_ADDR"));
        MarketFactory factory = MarketFactory(vm.envAddress("MARKET_FACTORY_ADDR"));
        IERC20 usdt = IERC20(vm.envAddress("USDT_ADDR"));

        // Get orderBook market ID from factory market #1
        (,,,,,,,uint256 obMarketId,,) = factory.marketMeta(1);
        require(obMarketId > 0, "Seed: no market found");

        console.log("Seeding market (OB ID):", obMarketId);

        // Anvil default private keys (accounts 1-8)
        uint256[5] memory bidKeys = [
            uint256(0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d),
            uint256(0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a),
            uint256(0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6),
            uint256(0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a),
            uint256(0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba)
        ];
        uint256[5] memory bidTicks = [uint256(45), uint256(50), uint256(55), uint256(60), uint256(65)];

        uint256[3] memory askKeys = [
            uint256(0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e),
            uint256(0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356),
            uint256(0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97)
        ];
        uint256[3] memory askTicks = [uint256(35), uint256(40), uint256(45)];

        // Place bid orders (accounts 1-5): approve USDT then place
        for (uint256 i = 0; i < 5; i++) {
            vm.startBroadcast(bidKeys[i]);
            usdt.approve(address(vault), type(uint256).max);
            uint256 orderId = orderBook.placeOrder(
                obMarketId, Side.Bid, OrderType.GoodTilCancel, bidTicks[i], 2
            );
            console.log("  Bid order", orderId, "at tick", bidTicks[i]);
            vm.stopBroadcast();
        }

        // Place ask orders (accounts 6-8)
        for (uint256 i = 0; i < 3; i++) {
            vm.startBroadcast(askKeys[i]);
            usdt.approve(address(vault), type(uint256).max);
            uint256 orderId = orderBook.placeOrder(
                obMarketId, Side.Ask, OrderType.GoodTilCancel, askTicks[i], 2
            );
            console.log("  Ask order", orderId, "at tick", askTicks[i]);
            vm.stopBroadcast();
        }

        console.log("Seed complete: 5 bids + 3 asks placed");
    }
}
