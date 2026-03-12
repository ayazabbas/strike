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
import {Redemption} from "../src/Redemption.sol";
import {MockPyth} from "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import {MockUSDT} from "../test/mocks/MockUSDT.sol";

/// @notice Deploy the full Strike protocol and seed a test market (devnet/anvil).
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

        // 1. MockUSDT (test collateral)
        MockUSDT usdt = new MockUSDT();

        // 2. FeeModel (20 bps = 0.20% uniform fee)
        FeeModel feeModel = new FeeModel(
            deployer,
            20,            // 0.20% uniform fee
            0,             // clearing bounty disabled
            5e18,          // resolver bounty (5 USDT)
            1e17,          // pruner bounty (0.1 USDT)
            deployer       // protocol fee collector
        );

        // 3. OutcomeToken
        OutcomeToken outcomeToken = new OutcomeToken(deployer);

        // 4. Vault (ERC20 collateral)
        Vault vault = new Vault(deployer, address(usdt));

        // 5. OrderBook
        OrderBook orderBook = new OrderBook(deployer, address(vault), address(feeModel));

        // 6. BatchAuction
        BatchAuction batchAuction = new BatchAuction(
            deployer,
            address(orderBook),
            address(vault),
            address(outcomeToken)
        );

        // 7. MockPyth (60s valid period, 1 wei fee)
        MockPyth mockPyth = new MockPyth(60, 1);

        // 8. MarketFactory
        MarketFactory factory = new MarketFactory(
            deployer,
            address(orderBook),
            address(outcomeToken),
            deployer // fee collector
        );

        // 9. PythResolver
        PythResolver pythResolver = new PythResolver(
            address(mockPyth),
            address(factory)
        );

        // 10. Redemption
        Redemption redemption = new Redemption(
            address(factory),
            address(outcomeToken),
            address(vault)
        );

        // 11. Wire roles
        orderBook.grantRole(orderBook.OPERATOR_ROLE(), address(batchAuction));
        orderBook.grantRole(orderBook.OPERATOR_ROLE(), address(factory));

        vault.grantRole(vault.PROTOCOL_ROLE(), address(orderBook));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(batchAuction));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(redemption));

        outcomeToken.grantRole(outcomeToken.MINTER_ROLE(), address(batchAuction));
        outcomeToken.grantRole(outcomeToken.MINTER_ROLE(), address(redemption));

        factory.grantRole(factory.ADMIN_ROLE(), address(pythResolver));
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), deployer);

        vm.stopBroadcast();

        // 12. Print deployed addresses as JSON
        string memory json = string.concat(
            '{"usdt":"', vm.toString(address(usdt)),
            '","feeModel":"', vm.toString(address(feeModel)),
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
            '","redemption":"', vm.toString(address(redemption)),
            '"}'
        );
        console.log(json);
    }
}
