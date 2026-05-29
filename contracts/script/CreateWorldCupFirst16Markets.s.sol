// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {USDTParimutuelV3Factory} from "../src/USDTParimutuelV3Factory.sol";
import {USDTParimutuelV3MarketConfig} from "../src/USDTParimutuelV3Types.sol";
import {WorldCupViewerMatchResolver} from "../src/WorldCupViewerMatchResolver.sol";

contract CreateWorldCupFirst16MarketsScript is Script {
    address internal constant DEFAULT_FACTORY = 0xbC7058cc868bD943606fF6cF1BB46c82009d00ca;
    address internal constant DEFAULT_WORLD_CUP_VIEWER = 0x00036192958C2aaAF9F445d3Cdc2979995EA333e;
    uint256 internal constant DEFAULT_CREDIT_EVENT_ID = 2026061101;

    struct MatchSpec {
        uint256 flapMatchId;
        string title;
        uint64 tradingCloseTime;
        uint64 resolutionTime;
        uint256 teamAId;
        uint256 drawId;
        uint256 teamBId;
    }

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address admin = vm.envOr("WORLD_CUP_MATCH_RESOLVER_ADMIN", deployer);
        address keeper = vm.envOr("WORLD_CUP_MATCH_RESOLVER_KEEPER", deployer);
        address factoryAddr = vm.envOr("USDT_PARIMUTUEL_V3_FACTORY", DEFAULT_FACTORY);
        address viewerAddr = vm.envOr("WORLD_CUP_VIEWER", DEFAULT_WORLD_CUP_VIEWER);
        uint256 creditEventId = vm.envOr("WORLD_CUP_CREDIT_EVENT_ID", DEFAULT_CREDIT_EVENT_ID);
        uint16 feeBps = uint16(vm.envOr("WORLD_CUP_MATCH_FEE_BPS", uint256(0)));
        bool creditEnabled = vm.envOr("WORLD_CUP_MATCH_CREDIT_ENABLED", true);

        USDTParimutuelV3Factory factory = USDTParimutuelV3Factory(factoryAddr);

        MatchSpec[16] memory specs = _specs();

        vm.startBroadcast(pk);

        WorldCupViewerMatchResolver resolver = new WorldCupViewerMatchResolver(admin, factoryAddr, viewerAddr);
        factory.grantRole(factory.ADMIN_ROLE(), address(resolver));
        resolver.grantRole(resolver.KEEPER_ROLE(), keeper);
        if (keeper != deployer) {
            resolver.grantRole(resolver.KEEPER_ROLE(), deployer);
        }

        console2.log("worldCupViewerMatchResolver", address(resolver));

        for (uint256 i = 0; i < specs.length; i++) {
            MatchSpec memory spec = specs[i];
            uint256 marketId = factory.createMarket(USDTParimutuelV3MarketConfig({
                tradingCloseTime: spec.tradingCloseTime,
                resolutionTime: spec.resolutionTime,
                outcomeCount: 3,
                feeBps: feeBps,
                creditEventId: creditEventId,
                creditEnabled: creditEnabled,
                metadataHash: keccak256(abi.encode("strike-world-cup-match", spec.flapMatchId, spec.title)),
                metadataURI: string.concat("strike://world-cup/2026/match/", vm.toString(spec.flapMatchId))
            }));

            uint256[] memory teamIds = new uint256[](3);
            teamIds[0] = spec.teamAId;
            teamIds[1] = spec.drawId;
            teamIds[2] = spec.teamBId;
            resolver.configureMarket(marketId, spec.flapMatchId, WorldCupViewerMatchResolver.QueryType.MatchResult, teamIds);

            console2.log("created", marketId, spec.flapMatchId, spec.title);
        }

        vm.stopBroadcast();
    }

    function _specs() internal pure returns (MatchSpec[16] memory specs) {
        // tradingCloseTime is official FIFA kick-off time in UTC.
        // resolutionTime is kick-off + 4 hours.
        specs[0] = MatchSpec(14, "Mexico vs South Africa", 1781204400, 1781218800, 1, 50, 2);
        specs[1] = MatchSpec(15, "South Korea vs Czechia", 1781229600, 1781244000, 3, 50, 4);
        specs[2] = MatchSpec(16, "Canada vs Bosnia and Herzegovina", 1781290800, 1781305200, 5, 50, 6);
        specs[3] = MatchSpec(17, "USA vs Paraguay", 1781312400, 1781326800, 13, 50, 14);
        specs[4] = MatchSpec(18, "Qatar vs Switzerland", 1781398800, 1781413200, 7, 50, 8);
        specs[5] = MatchSpec(19, "Brazil vs Morocco", 1781409600, 1781424000, 9, 50, 10);
        specs[6] = MatchSpec(20, "Haiti vs Scotland", 1781388000, 1781402400, 11, 50, 12);
        specs[7] = MatchSpec(21, "Australia vs Turkiye", 1781377200, 1781391600, 15, 50, 16);
        specs[8] = MatchSpec(22, "Germany vs Curacao", 1781478000, 1781492400, 17, 50, 18);
        specs[9] = MatchSpec(23, "Netherlands vs Japan", 1781456400, 1781470800, 21, 50, 22);
        specs[10] = MatchSpec(24, "Ivory Coast vs Ecuador", 1781467200, 1781481600, 19, 50, 20);
        specs[11] = MatchSpec(25, "Sweden vs Tunisia", 1781488800, 1781503200, 23, 50, 24);
        specs[12] = MatchSpec(26, "Spain vs Cape Verde", 1781560800, 1781575200, 29, 50, 30);
        specs[13] = MatchSpec(27, "Belgium vs Egypt", 1781539200, 1781553600, 25, 50, 26);
        specs[14] = MatchSpec(28, "Saudi Arabia vs Uruguay", 1781571600, 1781586000, 31, 50, 32);
        specs[15] = MatchSpec(29, "Iran vs New Zealand", 1781550000, 1781564400, 27, 50, 28);
    }
}
