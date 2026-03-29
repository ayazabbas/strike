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

contract DeployMainnetScript is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);
        
        // BSC Mainnet addresses
        address usdt = 0x55d398326f99059fF775485246999027B3197955;
        address pyth = 0x4D7E825f80bDf85e913E0DD2A2D54927e9dE1594;

        console.log("Deploying Strike to BSC Mainnet...");
        console.log("  Deployer:", deployer);

        vm.startBroadcast(pk);

        FeeModel feeModel = new FeeModel(deployer, 20, deployer);
        console.log("FeeModel:", address(feeModel));

        OutcomeToken outcomeToken = new OutcomeToken(deployer);
        console.log("OutcomeToken:", address(outcomeToken));

        Vault vault = new Vault(deployer, usdt);
        console.log("Vault:", address(vault));

        OrderBook orderBook = new OrderBook(deployer, address(vault), address(feeModel), address(outcomeToken));
        console.log("OrderBook:", address(orderBook));

        BatchAuction batchAuction = new BatchAuction(deployer, address(orderBook), address(vault), address(outcomeToken));
        console.log("BatchAuction:", address(batchAuction));

        MarketFactory factory = new MarketFactory(deployer, address(orderBook), address(outcomeToken));
        console.log("MarketFactory:", address(factory));

        PythResolver pythResolver = new PythResolver(pyth, address(factory));
        console.log("PythResolver:", address(pythResolver));

        Redemption redemption = new Redemption(address(factory), address(outcomeToken), address(vault));
        console.log("Redemption:", address(redemption));

        // Wire roles
        orderBook.grantRole(orderBook.OPERATOR_ROLE(), address(batchAuction));
        orderBook.grantRole(orderBook.OPERATOR_ROLE(), address(factory));

        vault.grantRole(vault.PROTOCOL_ROLE(), address(orderBook));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(batchAuction));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(redemption));

        outcomeToken.grantRole(outcomeToken.MINTER_ROLE(), address(batchAuction));
        outcomeToken.grantRole(outcomeToken.MINTER_ROLE(), address(redemption));
        outcomeToken.grantRole(outcomeToken.ESCROW_ROLE(), address(batchAuction));

        factory.grantRole(factory.ADMIN_ROLE(), address(pythResolver));
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), deployer);

        vm.stopBroadcast();
    }
}
