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
import {AIResolver} from "../src/AIResolver.sol";

contract DeployMainnetScript is Script {
    address internal constant USDT_BSC_MAINNET = 0x55d398326f99059fF775485246999027B3197955;
    address internal constant PYTH_BSC_MAINNET = 0x4D7E825f80bDf85e913E0DD2A2D54927e9dE1594;

    // BTC/USD Pyth price feed ID
    bytes32 internal constant BTC_USD_PRICE_ID = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;

    struct Deployed {
        address feeModel;
        address outcomeToken;
        address vault;
        address orderBook;
        address batchAuction;
        address factory;
        address pythResolver;
        address aiResolver;
        address redemption;
        address pyth;
        address usdt;
    }

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address keeper = vm.envOr("KEEPER_ADDRESS", deployer);
        address resolutionKeeper = vm.envOr("RESOLUTION_KEEPER_ADDRESS", address(0));
        if (resolutionKeeper == address(0)) {
            resolutionKeeper = vm.envOr("RESOLUTION_ADDRESS", keeper);
        }

        require(block.chainid == 56, "DeployMainnet: not BSC mainnet");

        console.log("Deploying Strike protocol to BSC Mainnet...");
        console.log("  Chain ID:", block.chainid);
        console.log("  Deployer:", deployer);
        console.log("  Keeper:", keeper);
        console.log("  Resolution keeper:", resolutionKeeper);
        console.log("  Pyth:", PYTH_BSC_MAINNET);
        console.log("  USDT:", USDT_BSC_MAINNET);

        Deployed memory d;
        d.pyth = PYTH_BSC_MAINNET;
        d.usdt = USDT_BSC_MAINNET;

        vm.startBroadcast(pk);

        FeeModel feeModel = new FeeModel(deployer, 20, deployer);
        d.feeModel = address(feeModel);

        OutcomeToken outcomeToken = new OutcomeToken(deployer);
        d.outcomeToken = address(outcomeToken);

        Vault vault = new Vault(deployer, USDT_BSC_MAINNET);
        d.vault = address(vault);

        OrderBook orderBook = new OrderBook(deployer, address(vault), address(feeModel), address(outcomeToken));
        d.orderBook = address(orderBook);

        BatchAuction batchAuction =
            new BatchAuction(deployer, address(orderBook), address(vault), address(outcomeToken));
        d.batchAuction = address(batchAuction);

        MarketFactory factory = new MarketFactory(deployer, address(orderBook), address(outcomeToken));
        d.factory = address(factory);

        PythResolver pythResolver = new PythResolver(PYTH_BSC_MAINNET, address(factory));
        d.pythResolver = address(pythResolver);

        AIResolver aiResolver = new AIResolver(address(factory), deployer);
        d.aiResolver = address(aiResolver);

        Redemption redemption = new Redemption(address(factory), address(outcomeToken), address(vault));
        d.redemption = address(redemption);

        _wireRoles(d, deployer, keeper, resolutionKeeper);

        vm.stopBroadcast();

        _printJson(d);
    }

    function _wireRoles(Deployed memory d, address deployer, address keeper, address resolutionKeeper) internal {
        OrderBook orderBook = OrderBook(d.orderBook);
        Vault vault = Vault(d.vault);
        OutcomeToken outcomeToken = OutcomeToken(d.outcomeToken);
        MarketFactory factory = MarketFactory(d.factory);
        AIResolver aiResolver = AIResolver(payable(d.aiResolver));

        orderBook.grantRole(orderBook.OPERATOR_ROLE(), d.batchAuction);
        orderBook.grantRole(orderBook.OPERATOR_ROLE(), d.factory);
        orderBook.grantRole(orderBook.OPERATOR_ROLE(), keeper);

        vault.grantRole(vault.PROTOCOL_ROLE(), d.orderBook);
        vault.grantRole(vault.PROTOCOL_ROLE(), d.batchAuction);
        vault.grantRole(vault.PROTOCOL_ROLE(), d.redemption);

        outcomeToken.grantRole(outcomeToken.MINTER_ROLE(), d.batchAuction);
        outcomeToken.grantRole(outcomeToken.MINTER_ROLE(), d.redemption);
        outcomeToken.grantRole(outcomeToken.ESCROW_ROLE(), d.batchAuction);

        factory.grantRole(factory.ADMIN_ROLE(), d.pythResolver);
        factory.grantRole(factory.ADMIN_ROLE(), d.aiResolver);
        factory.grantRole(factory.ADMIN_ROLE(), keeper);
        factory.grantRole(factory.ADMIN_ROLE(), resolutionKeeper);
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), deployer);
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), keeper);
        factory.setAIResolver(d.aiResolver);

        aiResolver.grantRole(aiResolver.KEEPER_ROLE(), keeper);
        aiResolver.grantRole(aiResolver.KEEPER_ROLE(), resolutionKeeper);
    }

    function _printJson(Deployed memory d) internal view {
        string memory json = string.concat(
            '{"feeModel":"',
            vm.toString(d.feeModel),
            '","outcomeToken":"',
            vm.toString(d.outcomeToken),
            '","vault":"',
            vm.toString(d.vault),
            '","orderBook":"',
            vm.toString(d.orderBook),
            '","batchAuction":"',
            vm.toString(d.batchAuction),
            '","pyth":"',
            vm.toString(d.pyth)
        );
        json = string.concat(
            json,
            '","usdt":"',
            vm.toString(d.usdt),
            '","marketFactory":"',
            vm.toString(d.factory),
            '","pythResolver":"',
            vm.toString(d.pythResolver),
            '","aiResolver":"',
            vm.toString(d.aiResolver),
            '","redemption":"',
            vm.toString(d.redemption),
            '","btcUsdPriceId":"',
            vm.toString(BTC_USD_PRICE_ID),
            '"}'
        );
        console.log(json);
    }
}
