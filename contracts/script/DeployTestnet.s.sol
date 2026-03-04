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

/// @notice Deploy Strike protocol to BSC testnet or mainnet using real Pyth Core.
contract DeployTestnetScript is Script {
    // Real Pyth Core addresses
    address constant PYTH_BSC_TESTNET = 0xd7308b14BF4008e7C7196eC35610B1427C5702EA;
    address constant PYTH_BSC_MAINNET = 0x4D7E825f80bDf85e913E0DD2A2D54927e9dE1594;

    // BTC/USD Pyth price feed ID
    bytes32 constant BTC_USD_PRICE_ID = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;

    struct Deployed {
        address feeModel;
        address outcomeToken;
        address vault;
        address orderBook;
        address batchAuction;
        address factory;
        address pythResolver;
        address pyth;
        uint256 testMarketId;
    }

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        address pythAddr = block.chainid == 97
            ? PYTH_BSC_TESTNET
            : PYTH_BSC_MAINNET;

        require(block.chainid == 97 || block.chainid == 56, "DeployTestnet: unsupported chain");

        console.log("Deploying Strike protocol...");
        console.log("  Chain ID:", block.chainid);
        console.log("  Deployer:", deployer);
        console.log("  Pyth:", pythAddr);

        Deployed memory d;
        d.pyth = pythAddr;

        vm.startBroadcast(pk);

        FeeModel feeModel = new FeeModel(deployer, 30, 0, 0.005 ether, 0.0001 ether, deployer);
        d.feeModel = address(feeModel);

        OutcomeToken outcomeToken = new OutcomeToken(deployer);
        d.outcomeToken = address(outcomeToken);

        Vault vault = new Vault(deployer);
        d.vault = address(vault);

        OrderBook orderBook = new OrderBook(deployer, address(vault));
        d.orderBook = address(orderBook);

        BatchAuction batchAuction = new BatchAuction(deployer, address(orderBook), address(vault), address(feeModel), address(outcomeToken));
        d.batchAuction = address(batchAuction);

        MarketFactory factory = new MarketFactory(deployer, address(orderBook), address(outcomeToken), deployer);
        d.factory = address(factory);

        PythResolver pythResolver = new PythResolver(pythAddr, address(factory));
        d.pythResolver = address(pythResolver);

        // Wire roles
        orderBook.grantRole(orderBook.OPERATOR_ROLE(), address(batchAuction));
        orderBook.grantRole(orderBook.OPERATOR_ROLE(), address(factory));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(orderBook));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(batchAuction));
        outcomeToken.grantRole(outcomeToken.MINTER_ROLE(), address(batchAuction));
        factory.grantRole(factory.ADMIN_ROLE(), address(pythResolver));

        // Create test market: BTC/USD, 1 hour, 12s batches
        d.testMarketId = factory.createMarket{value: 0.01 ether}(BTC_USD_PRICE_ID, 3600, 12, 1);

        vm.stopBroadcast();

        _printJson(d);
    }

    function _printJson(Deployed memory d) internal view {
        string memory json = string.concat(
            '{"feeModel":"', vm.toString(d.feeModel),
            '","outcomeToken":"', vm.toString(d.outcomeToken),
            '","vault":"', vm.toString(d.vault),
            '","orderBook":"', vm.toString(d.orderBook),
            '","batchAuction":"', vm.toString(d.batchAuction),
            '","pyth":"', vm.toString(d.pyth)
        );
        json = string.concat(
            json,
            '","marketFactory":"', vm.toString(d.factory),
            '","pythResolver":"', vm.toString(d.pythResolver),
            '","testMarketFactoryId":"', vm.toString(d.testMarketId),
            '","btcUsdPriceId":"', vm.toString(BTC_USD_PRICE_ID),
            '"}'
        );
        console.log(json);
    }
}
