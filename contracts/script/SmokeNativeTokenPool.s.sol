// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NativeTokenParimutuelFactory} from "../src/NativeTokenParimutuelFactory.sol";
import {NativeTokenPoolManager} from "../src/NativeTokenPoolManager.sol";
import {NativeTokenPoolMarketConfig} from "../src/NativeTokenPoolTypes.sol";
import {ParimutuelCurveType} from "../src/ParimutuelTypes.sol";

interface IWBNB is IERC20 {
    function deposit() external payable;
}

contract SmokeNativeTokenPoolScript is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address creator = vm.addr(pk);
        NativeTokenParimutuelFactory factory = NativeTokenParimutuelFactory(vm.envAddress("NATIVE_TOKEN_POOL_FACTORY"));
        NativeTokenPoolManager manager = NativeTokenPoolManager(vm.envAddress("NATIVE_TOKEN_POOL_MANAGER_ADDR"));
        IWBNB collateral = IWBNB(vm.envOr("NATIVE_TOKEN_POOL_COLLATERAL_TOKEN", address(0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd)));

        uint64 tradingCloseTime = uint64(vm.envUint("SMOKE_TRADING_CLOSE_TIME"));
        uint64 resolutionTime = uint64(vm.envUint("SMOKE_RESOLUTION_TIME"));
        bytes32 metadataHash = vm.envBytes32("SMOKE_METADATA_HASH");
        string memory metadataURI = vm.envString("SMOKE_METADATA_URI");
        string memory prompt = vm.envString("SMOKE_PROMPT");

        uint256 creatorBond = factory.creatorBondAmount();
        uint256 buyYes = vm.envOr("SMOKE_BUY_YES_WEI", uint256(0.01 ether));
        uint256 buyNo = vm.envOr("SMOKE_BUY_NO_WEI", uint256(0.005 ether));
        uint256 minStake = vm.envOr("SMOKE_MIN_STAKE_WEI", uint256(0.001 ether));
        uint256 totalBuy = buyYes + buyNo;

        console.log("Smoke native token pool");
        console.log("  Creator:", creator);
        console.log("  Factory:", address(factory));
        console.log("  Manager:", address(manager));
        console.log("  Collateral:", address(collateral));
        console.log("  Creator bond wei:", creatorBond);
        console.log("  Trading close:", tradingCloseTime);
        console.log("  Resolution:", resolutionTime);
        console.log("  Metadata hash:");
        console.logBytes32(metadataHash);
        console.log("  Metadata URI:", metadataURI);

        NativeTokenPoolMarketConfig memory config = NativeTokenPoolMarketConfig({
            collateralToken: address(collateral),
            tradingCloseTime: tradingCloseTime,
            resolutionTime: resolutionTime,
            outcomeCount: 2,
            curveType: ParimutuelCurveType.Flat,
            curveParam: 0,
            feeBps: factory.platformFeeBps(),
            minStake: minStake,
            maxStake: 0,
            metadataHash: metadataHash,
            metadataURI: metadataURI,
            prompt: prompt
        });

        vm.startBroadcast(pk);
        if (collateral.balanceOf(creator) < totalBuy) {
            collateral.deposit{value: totalBuy - collateral.balanceOf(creator)}();
        }
        uint256 marketId = factory.createNativePoolMarket{value: creatorBond}(config);
        collateral.approve(address(manager), totalBuy);
        uint256 yesShares = manager.buy(marketId, 0, buyYes, 0);
        uint256 noShares = manager.buy(marketId, 1, buyNo, 0);
        vm.stopBroadcast();

        console.log("  Market ID:", marketId);
        console.log("  YES shares:", yesShares);
        console.log("  NO shares:", noShares);
    }
}
