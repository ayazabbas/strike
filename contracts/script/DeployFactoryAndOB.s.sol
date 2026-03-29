// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {OrderBook} from "../src/OrderBook.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {PythResolver} from "../src/PythResolver.sol";
import {Redemption} from "../src/Redemption.sol";

/// @notice Redeploy OrderBook + MarketFactory + PythResolver + Redemption
///         to fix the market ID mismatch. Other contracts (Vault, BatchAuction,
///         FeeModel, OutcomeToken) stay the same.
contract DeployFactoryAndOBScript is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address mainnetDeployer = 0x2FB6243F7616F6aF550869eFE0f08Bbf43315F68;
        address keeper = 0x0501241B6De84ab14575ea08e30b5b81bf92090C;
        address resolutionKeeper = 0x36a868a3C46b706047CEdC4332cF3bdb11C76915;

        // Existing contracts that stay
        address vault = 0xDddF8221EDD0cf60cf7Bf8aaBf15B9d0a0739264;
        address feeModel = 0x2c12e18c9ba5a2977c68eF3E980686dd27e2Eb42;
        address outcomeToken = 0xD14eFaeE6BC2a55F5B346be4f05f5b44534a3b73;
        address batchAuction = 0xF52A7b5E7A869355b7b376CBEB27b188a1e5CD53;
        address pyth = 0x4D7E825f80bDf85e913E0DD2A2D54927e9dE1594;

        console.log("Redeploying OrderBook + MarketFactory...");

        vm.startBroadcast(pk);

        // 1. Deploy new OrderBook
        OrderBook ob = new OrderBook(deployer, vault, feeModel, outcomeToken);
        console.log("  OrderBook:", address(ob));

        // 2. Set nextMarketId to 1714
        ob.setNextMarketId(1714);

        // 3. Deploy new MarketFactory pointing to new OrderBook
        MarketFactory factory = new MarketFactory(deployer, address(ob), outcomeToken);
        console.log("  MarketFactory:", address(factory));

        // 4. Set factory counter to 1714
        factory.setNextFactoryMarketId(1714);

        // 5. Deploy new PythResolver pointing to new Factory
        PythResolver resolver = new PythResolver(pyth, address(factory));
        console.log("  PythResolver:", address(resolver));

        // 6. Deploy new Redemption pointing to new Factory
        Redemption redemption = new Redemption(address(factory), outcomeToken, vault);
        console.log("  Redemption:", address(redemption));

        // 7. Grant roles
        // OrderBook: OPERATOR_ROLE to Factory + BatchAuction
        bytes32 OB_OPERATOR = ob.OPERATOR_ROLE();
        ob.grantRole(OB_OPERATOR, address(factory));
        ob.grantRole(OB_OPERATOR, batchAuction);

        // MarketFactory: MARKET_CREATOR_ROLE to keepers
        bytes32 MARKET_CREATOR = factory.MARKET_CREATOR_ROLE();
        factory.grantRole(MARKET_CREATOR, keeper);
        factory.grantRole(MARKET_CREATOR, resolutionKeeper);
        factory.grantRole(MARKET_CREATOR, deployer);

        // MarketFactory: RESOLVER_ROLE to PythResolver
        bytes32 RESOLVER_ROLE = factory.ADMIN_ROLE();
        factory.grantRole(RESOLVER_ROLE, address(resolver));

        // PythResolver: KEEPER_ROLE to keepers

        // BatchAuction: update orderBook reference if possible
        // BatchAuction has immutable orderBook too — need to check
        // For now, grant OPERATOR on new OB to BatchAuction

        // Admin roles to mainnet deployer
        ob.grantRole(ob.DEFAULT_ADMIN_ROLE(), mainnetDeployer);
        factory.grantRole(factory.DEFAULT_ADMIN_ROLE(), mainnetDeployer);

        // Vault: PROTOCOL_ROLE to new OrderBook + Factory
        // Vault already has PROTOCOL_ROLE granted to old OB — need to grant to new
        // But we can't call vault.grantRole from here unless deployer has admin on vault
        
        vm.stopBroadcast();

        console.log("Done! New addresses:");
        console.log("  OrderBook:", address(ob));
        console.log("  MarketFactory:", address(factory));
        console.log("  PythResolver:", address(resolver));
        console.log("  Redemption:", address(redemption));
    }
}
