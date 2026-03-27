// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/AIResolver.sol";
import "../src/MarketFactory.sol";

contract DeployAIResolver is Script {
    function run() external {
        address factoryAddr = vm.envAddress("FACTORY_ADDRESS");
        address treasuryAddr = vm.envAddress("TREASURY_ADDRESS");
        address keeperAddr = vm.envAddress("KEEPER_ADDRESS");

        vm.startBroadcast();

        // 1. Deploy AIResolver
        AIResolver aiResolver = new AIResolver(factoryAddr, treasuryAddr);

        // 2. Set AIResolver on factory
        MarketFactory factory = MarketFactory(factoryAddr);
        factory.setAIResolver(address(aiResolver));

        // 3. Grant AIResolver ADMIN_ROLE on factory (so it can call setResolved/setResolving)
        factory.grantRole(factory.ADMIN_ROLE(), address(aiResolver));

        // 4. Grant keeper KEEPER_ROLE on AIResolver
        aiResolver.grantRole(aiResolver.KEEPER_ROLE(), keeperAddr);

        vm.stopBroadcast();

        console.log("AIResolver deployed at:", address(aiResolver));
        console.log("Factory:", factoryAddr);
        console.log("Treasury:", treasuryAddr);
        console.log("Keeper:", keeperAddr);
    }
}
