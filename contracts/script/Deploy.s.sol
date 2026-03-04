// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {FeeModel} from "../src/FeeModel.sol";
import {OutcomeToken} from "../src/OutcomeToken.sol";
import {Vault} from "../src/Vault.sol";
import {OrderBook} from "../src/OrderBook.sol";
import {BatchAuction} from "../src/BatchAuction.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {PythResolver} from "../src/PythResolver.sol";
import {MockPyth} from "./mocks/MockPyth.sol";

/// @notice Deploy the full Strike protocol and seed a test market.
///
///   Deployment order (PythResolver.factory is immutable, so MarketFactory
///   must be deployed first):
///
///     1. FeeModel
///     2. OutcomeToken
///     3. Vault
///     4. OrderBook
///     5. BatchAuction
///     6. MockPyth
///     7. MarketFactory      (needs orderBook, outcomeToken)
///     8. PythResolver        (needs mockPyth, factory)
///     9. Wire roles
///    10. Set Lazer feed ID mapping
///    11. Create test market
///    12. Print addresses as JSON
contract DeployScript is Script {
    function run() external {
        // Default to anvil account 0 if PRIVATE_KEY not set
        uint256 pk = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(pk);

        console.log("Deploying Strike protocol...");
        console.log("  Chain ID:", block.chainid);
        console.log("  Deployer:", deployer);

        vm.startBroadcast(pk);

        // 1. FeeModel
        FeeModel feeModel = new FeeModel(
            deployer,
            30,            // 0.30% taker fee
            0,             // 0% maker rebate
            0.005 ether,   // resolver bounty
            0.0001 ether,  // pruner bounty
            deployer       // protocol fee collector
        );

        // 2. OutcomeToken
        OutcomeToken outcomeToken = new OutcomeToken(deployer);

        // 3. Vault
        Vault vault = new Vault(deployer);

        // 4. OrderBook
        OrderBook orderBook = new OrderBook(deployer, address(vault));

        // 5. BatchAuction
        BatchAuction batchAuction = new BatchAuction(
            deployer,
            address(orderBook),
            address(vault),
            address(feeModel),
            address(outcomeToken)
        );

        // 6. MockPyth
        MockPyth mockPyth = new MockPyth();

        // 7. MarketFactory
        MarketFactory factory = new MarketFactory(
            deployer,
            address(orderBook),
            address(outcomeToken),
            deployer // fee collector
        );

        // 8. PythResolver
        PythResolver pythResolver = new PythResolver(
            address(mockPyth),
            address(factory)
        );

        // 9. Wire roles
        orderBook.grantRole(orderBook.OPERATOR_ROLE(), address(batchAuction));
        orderBook.grantRole(orderBook.OPERATOR_ROLE(), address(factory));

        vault.grantRole(vault.PROTOCOL_ROLE(), address(orderBook));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(batchAuction));

        outcomeToken.grantRole(outcomeToken.MINTER_ROLE(), address(batchAuction));

        factory.grantRole(factory.ADMIN_ROLE(), address(pythResolver));

        // 10. Map mock BTC/USD priceId → Lazer feedId 1
        bytes32 priceId = bytes32(uint256(1));
        pythResolver.setLazerFeedId(priceId, 1);

        // Seed MockPyth with a price (useful for later resolution testing)
        mockPyth.setPrice(
            1,                           // feedId
            int64(int256(50000_00000000)), // BTC ~$50,000 (8 decimals)
            uint64(500_00000000),         // $500 confidence
            uint64(block.timestamp)
        );

        // 11. Create test market: BTC/USD, 1 hour, 12s batches
        uint256 factoryMarketId = factory.createMarket{value: 0.01 ether}(
            priceId,
            3600,  // 1 hour duration
            12,    // 12s batch interval
            1      // min 1 lot
        );

        vm.stopBroadcast();

        // 12. Print deployed addresses as JSON (grep-able by deploy container)
        string memory json = string.concat(
            '{"feeModel":"', vm.toString(address(feeModel)),
            '","outcomeToken":"', vm.toString(address(outcomeToken)),
            '","vault":"', vm.toString(address(vault)),
            '","orderBook":"', vm.toString(address(orderBook)),
            '","batchAuction":"', vm.toString(address(batchAuction)),
            '","mockPyth":"', vm.toString(address(mockPyth))
        );
        json = string.concat(
            json,
            '","marketFactory":"', vm.toString(address(factory)),
            '","pythResolver":"', vm.toString(address(pythResolver)),
            '","testMarketFactoryId":"', vm.toString(factoryMarketId),
            '"}'
        );
        console.log(json);
    }
}
