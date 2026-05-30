// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {USDTParimutuelV3Factory} from "../src/USDTParimutuelV3Factory.sol";
import {USDTParimutuelV3MarketConfig} from "../src/USDTParimutuelV3Types.sol";
import {WorldCupViewerMatchResolver} from "../src/WorldCupViewerMatchResolver.sol";
import {WorldCupViewerContinentResolver} from "../src/WorldCupViewerContinentResolver.sol";

contract CreateWorldCupFuturesMarketsScript is Script {
    address internal constant DEFAULT_FACTORY = 0xbC7058cc868bD943606fF6cF1BB46c82009d00ca;
    address internal constant DEFAULT_WORLD_CUP_VIEWER = 0x00036192958C2aaAF9F445d3Cdc2979995EA333e;
    address internal constant DEFAULT_MATCH_RESOLVER = 0x0b7B13C301eC4543554e2E95c667D1078Ee4D255;
    uint256 internal constant DEFAULT_CREDIT_EVENT_ID = 2026061101;
    uint64 internal constant GROUP_TRADING_CLOSE_TIME = 1782518400; // 2026-06-27 00:00 UTC
    uint64 internal constant GROUP_RESOLUTION_TIME = 1782532800; // 2026-06-27 04:00 UTC
    uint64 internal constant FINAL_TRADING_CLOSE_TIME = 1784505600; // 2026-07-20 00:00 UTC
    uint64 internal constant FINAL_RESOLUTION_TIME = 1784520000; // 2026-07-20 04:00 UTC

    struct GroupSpec {
        string letter;
        uint256 viewerMatchId;
        uint256[5] teamIds;
        string[5] labels;
    }

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address admin = vm.envOr("WORLD_CUP_FUTURES_ADMIN", deployer);
        address keeper = vm.envOr("WORLD_CUP_MATCH_RESOLVER_KEEPER", deployer);
        address factoryAddr = vm.envOr("USDT_PARIMUTUEL_V3_FACTORY", DEFAULT_FACTORY);
        address viewerAddr = vm.envOr("WORLD_CUP_VIEWER", DEFAULT_WORLD_CUP_VIEWER);
        address matchResolverAddr = vm.envOr("WORLD_CUP_MATCH_RESOLVER", DEFAULT_MATCH_RESOLVER);
        uint256 creditEventId = vm.envOr("WORLD_CUP_CREDIT_EVENT_ID", DEFAULT_CREDIT_EVENT_ID);
        uint16 feeBps = uint16(vm.envOr("WORLD_CUP_FUTURES_FEE_BPS", uint256(0)));
        bool creditEnabled = vm.envOr("WORLD_CUP_FUTURES_CREDIT_ENABLED", true);

        USDTParimutuelV3Factory factory = USDTParimutuelV3Factory(factoryAddr);
        WorldCupViewerMatchResolver groupResolver = WorldCupViewerMatchResolver(matchResolverAddr);
        GroupSpec[12] memory groups = _groups();

        vm.startBroadcast(pk);

        WorldCupViewerContinentResolver continentResolver = new WorldCupViewerContinentResolver(admin, factoryAddr, viewerAddr);
        factory.grantRole(factory.ADMIN_ROLE(), address(continentResolver));
        continentResolver.grantRole(continentResolver.KEEPER_ROLE(), keeper);
        if (keeper != deployer) {
            continentResolver.grantRole(continentResolver.KEEPER_ROLE(), deployer);
        }
        console2.log("worldCupViewerContinentResolver", address(continentResolver));

        uint256 continentMarketId = factory.createMarket(USDTParimutuelV3MarketConfig({
            tradingCloseTime: FINAL_TRADING_CLOSE_TIME,
            resolutionTime: FINAL_RESOLUTION_TIME,
            outcomeCount: 7,
            feeBps: feeBps,
            creditEventId: creditEventId,
            creditEnabled: creditEnabled,
            metadataHash: keccak256(bytes(_continentMetadataURI())),
            metadataURI: _continentMetadataURI()
        }));
        (uint256[] memory continentTeamIds, uint8[] memory continentOutcomeIds) = _continentMappings();
        continentResolver.configureMarket(continentMarketId, continentTeamIds, continentOutcomeIds);
        console2.log("created continent", continentMarketId);

        for (uint256 i = 0; i < groups.length; i++) {
            GroupSpec memory spec = groups[i];
            string memory uri = _groupMetadataURI(spec);
            uint256 marketId = factory.createMarket(USDTParimutuelV3MarketConfig({
                tradingCloseTime: GROUP_TRADING_CLOSE_TIME,
                resolutionTime: GROUP_RESOLUTION_TIME,
                outcomeCount: 5,
                feeBps: feeBps,
                creditEventId: creditEventId,
                creditEnabled: creditEnabled,
                metadataHash: keccak256(bytes(uri)),
                metadataURI: uri
            }));

            uint256[] memory teamIds = new uint256[](5);
            for (uint256 j = 0; j < 5; j++) {
                teamIds[j] = spec.teamIds[j];
            }
            groupResolver.configureMarket(marketId, spec.viewerMatchId, WorldCupViewerMatchResolver.QueryType.GroupWinner, teamIds);
            console2.log("created group", marketId, spec.viewerMatchId, spec.letter);
        }

        vm.stopBroadcast();
    }

    function _continentMetadataURI() internal pure returns (string memory) {
        return string.concat(
            "data:application/json;utf8,",
            "%7B%22question%22%3A%22Which%20continent%20will%20win%20the%202026%20FIFA%20World%20Cup%3F%22%2C",
            "%22category%22%3A%22World%20Cup%22%2C%22kind%22%3A%22world_cup_continent_winner%22%2C",
            "%22source%22%3A%22FLAP%20World%20Cup%20Viewer%22%2C%22outcomes%22%3A%5B",
            "%7B%22id%22%3A0%2C%22label%22%3A%22Africa%22%7D%2C",
            "%7B%22id%22%3A1%2C%22label%22%3A%22Asia%22%7D%2C",
            "%7B%22id%22%3A2%2C%22label%22%3A%22Europe%22%7D%2C",
            "%7B%22id%22%3A3%2C%22label%22%3A%22North%20America%22%7D%2C",
            "%7B%22id%22%3A4%2C%22label%22%3A%22South%20America%22%7D%2C",
            "%7B%22id%22%3A5%2C%22label%22%3A%22Oceania%22%7D%2C",
            "%7B%22id%22%3A6%2C%22label%22%3A%22Other%22%7D%5D%7D"
        );
    }

    function _groupMetadataURI(GroupSpec memory spec) internal pure returns (string memory) {
        return string.concat(
            "data:application/json;utf8,%7B%22question%22%3A%22Who%20will%20win%202026%20FIFA%20World%20Cup%20Group%20",
            spec.letter,
            "%3F%22%2C%22category%22%3A%22World%20Cup%22%2C%22kind%22%3A%22world_cup_group_winner%22%2C%22group%22%3A%22",
            spec.letter,
            "%22%2C%22source%22%3A%22FLAP%20World%20Cup%20Viewer%22%2C%22outcomes%22%3A%5B",
            _outcomeJson(0, spec.labels[0]), ",", _outcomeJson(1, spec.labels[1]), ",", _outcomeJson(2, spec.labels[2]), ",",
            _outcomeJson(3, spec.labels[3]), ",", _outcomeJson(4, spec.labels[4]), "%5D%7D"
        );
    }

    function _outcomeJson(uint256 id, string memory encodedLabel) internal pure returns (string memory) {
        return string.concat("%7B%22id%22%3A", vm.toString(id), "%2C%22label%22%3A%22", encodedLabel, "%22%7D");
    }

    function _groups() internal pure returns (GroupSpec[12] memory groups) {
        groups[0] = GroupSpec("A", 2, [uint256(1), 2, 3, 4, 49], ["Mexico", "South%20Africa", "South%20Korea", "Czechia", "Other"]);
        groups[1] = GroupSpec("B", 3, [uint256(5), 6, 7, 8, 49], ["Canada", "Bosnia%20and%20Herzegovina", "Qatar", "Switzerland", "Other"]);
        groups[2] = GroupSpec("C", 4, [uint256(9), 10, 11, 12, 49], ["Brazil", "Morocco", "Haiti", "Scotland", "Other"]);
        groups[3] = GroupSpec("D", 5, [uint256(13), 14, 15, 16, 49], ["USA", "Paraguay", "Australia", "Turkiye", "Other"]);
        groups[4] = GroupSpec("E", 6, [uint256(17), 18, 19, 20, 49], ["Germany", "Curacao", "Ivory%20Coast", "Ecuador", "Other"]);
        groups[5] = GroupSpec("F", 7, [uint256(21), 22, 23, 24, 49], ["Netherlands", "Japan", "Sweden", "Tunisia", "Other"]);
        groups[6] = GroupSpec("G", 8, [uint256(25), 26, 27, 28, 49], ["Belgium", "Egypt", "Iran", "New%20Zealand", "Other"]);
        groups[7] = GroupSpec("H", 9, [uint256(29), 30, 31, 32, 49], ["Spain", "Cape%20Verde", "Saudi%20Arabia", "Uruguay", "Other"]);
        groups[8] = GroupSpec("I", 10, [uint256(33), 34, 35, 36, 49], ["France", "Senegal", "Iraq", "Norway", "Other"]);
        groups[9] = GroupSpec("J", 11, [uint256(37), 38, 39, 40, 49], ["Argentina", "Algeria", "Austria", "Jordan", "Other"]);
        groups[10] = GroupSpec("K", 12, [uint256(41), 42, 43, 44, 49], ["Portugal", "DR%20Congo", "Uzbekistan", "Colombia", "Other"]);
        groups[11] = GroupSpec("L", 13, [uint256(45), 46, 47, 48, 49], ["England", "Croatia", "Ghana", "Panama", "Other"]);
    }

    function _continentMappings() internal pure returns (uint256[] memory teamIds, uint8[] memory outcomeIds) {
        teamIds = new uint256[](49);
        outcomeIds = new uint8[](49);
        uint256 i;
        // Africa = 0
        uint256[10] memory africa = [uint256(2), 10, 19, 24, 26, 30, 34, 38, 42, 47];
        for (uint256 j = 0; j < africa.length; j++) { teamIds[i] = africa[j]; outcomeIds[i++] = 0; }
        // Asia = 1
        uint256[8] memory asia = [uint256(3), 7, 22, 27, 31, 35, 40, 43];
        for (uint256 j = 0; j < asia.length; j++) { teamIds[i] = asia[j]; outcomeIds[i++] = 1; }
        // Europe = 2
        uint256[16] memory europe = [uint256(4), 6, 8, 12, 16, 17, 21, 23, 25, 29, 33, 36, 39, 41, 45, 46];
        for (uint256 j = 0; j < europe.length; j++) { teamIds[i] = europe[j]; outcomeIds[i++] = 2; }
        // North America = 3
        uint256[6] memory northAmerica = [uint256(1), 5, 11, 13, 18, 48];
        for (uint256 j = 0; j < northAmerica.length; j++) { teamIds[i] = northAmerica[j]; outcomeIds[i++] = 3; }
        // South America = 4
        uint256[6] memory southAmerica = [uint256(9), 14, 20, 32, 37, 44];
        for (uint256 j = 0; j < southAmerica.length; j++) { teamIds[i] = southAmerica[j]; outcomeIds[i++] = 4; }
        // Oceania = 5
        uint256[2] memory oceania = [uint256(15), 28];
        for (uint256 j = 0; j < oceania.length; j++) { teamIds[i] = oceania[j]; outcomeIds[i++] = 5; }
        // Other = 6
        teamIds[i] = 49; outcomeIds[i++] = 6;
    }
}
