// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {OrderBook} from "../src/OrderBook.sol";

contract DeployOrderBookScript is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        address vault = 0xDddF8221EDD0cf60cf7Bf8aaBf15B9d0a0739264;
        address feeModel = 0x2c12e18c9ba5a2977c68eF3E980686dd27e2Eb42;
        address outcomeToken = 0xD14eFaeE6BC2a55F5B346be4f05f5b44534a3b73;

        console.log("Deploying OrderBook...");
        console.log("  Deployer:", deployer);

        vm.startBroadcast(pk);

        OrderBook ob = new OrderBook(deployer, vault, feeModel, outcomeToken);
        console.log("  OrderBook:", address(ob));

        // Set nextMarketId to 1714 to match factory
        ob.setNextMarketId(1714);
        console.log("  nextMarketId set to 1714");

        // Grant OPERATOR_ROLE to MarketFactory
        bytes32 OPERATOR_ROLE = ob.OPERATOR_ROLE();
        ob.grantRole(OPERATOR_ROLE, 0x912d5C25AFd8807904B6F804b4eDCD611ac64396); // Factory
        console.log("  OPERATOR_ROLE granted to Factory");

        // Grant OPERATOR_ROLE to BatchAuction
        ob.grantRole(OPERATOR_ROLE, 0xF52A7b5E7A869355b7b376CBEB27b188a1e5CD53); // BatchAuction
        console.log("  OPERATOR_ROLE granted to BatchAuction");

        // Grant admin to mainnet deployer too
        ob.grantRole(ob.DEFAULT_ADMIN_ROLE(), 0x2FB6243F7616F6aF550869eFE0f08Bbf43315F68);

        vm.stopBroadcast();

        console.log("Done! Update ORDER_BOOK_ADDR everywhere.");
    }
}
