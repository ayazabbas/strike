// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/ParimutuelFactory.sol";
import "../src/ParimutuelTypes.sol";
import "../src/WorldCupViewerParimutuelResolver.sol";

contract MockWorldCupViewerForParimutuel {
    struct MatchViewResult {
        uint256 matchId;
        string matchName;
        bool isResolved;
        uint256 teamId;
        string teamName;
    }

    mapping(uint256 => MatchViewResult) internal _matchResults;

    function setMatchResult(uint256 matchId, bool isResolved, uint256 teamId, string calldata teamName) external {
        _matchResults[matchId] = MatchViewResult({
            matchId: matchId, matchName: "match", isResolved: isResolved, teamId: teamId, teamName: teamName
        });
    }

    function getMatchResult(uint256 matchId) external view returns (MatchViewResult memory) {
        return _matchResults[matchId];
    }

    function getGroupMatchWinners(uint256 matchId) external view returns (MatchViewResult memory) {
        return _matchResults[matchId];
    }

    function getWorldCupWinner() external view returns (MatchViewResult memory) {
        return _matchResults[1];
    }

    function getTeamName(uint256) external pure returns (string memory) {
        return "";
    }
}

contract WorldCupViewerParimutuelResolverTest is Test {
    address internal admin = address(0xA11CE);
    address internal keeper = address(0xB0B);

    ParimutuelFactory internal factory;
    MockWorldCupViewerForParimutuel internal viewer;
    WorldCupViewerParimutuelResolver internal resolver;

    function setUp() public {
        factory = new ParimutuelFactory(admin);
        viewer = new MockWorldCupViewerForParimutuel();
        resolver = new WorldCupViewerParimutuelResolver(admin, address(factory), address(viewer));

        bytes32 marketCreatorRole = factory.MARKET_CREATOR_ROLE();
        bytes32 factoryAdminRole = factory.ADMIN_ROLE();
        bytes32 keeperRole = resolver.KEEPER_ROLE();

        vm.startPrank(admin);
        factory.grantRole(marketCreatorRole, admin);
        factory.grantRole(factoryAdminRole, address(resolver));
        resolver.grantRole(keeperRole, keeper);
        vm.stopPrank();
    }

    function test_resolveAdminWorldCupMatchClosesAndResolvesFromViewer() public {
        uint256 marketId = _createMarket(3);
        uint256[] memory teamIds = new uint256[](3);
        teamIds[0] = 1;
        teamIds[1] = 50;
        teamIds[2] = 2;

        vm.prank(admin);
        resolver.configureMarket(marketId, 14, WorldCupViewerParimutuelResolver.QueryType.MatchResult, teamIds);
        viewer.setMatchResult(14, true, 2, "South Africa");

        vm.warp(block.timestamp + 2 days);
        vm.prank(keeper);
        resolver.resolveMarket(marketId);

        ParimutuelMarket memory market = factory.getMarket(marketId);
        assertEq(uint8(market.state), uint8(ParimutuelMarketState.Resolved));
        assertEq(market.winningOutcomeId, 2);
    }

    function test_revertsWhenAdminMarketViewerResultPending() public {
        uint256 marketId = _createMarket(3);
        uint256[] memory teamIds = new uint256[](3);
        teamIds[0] = 1;
        teamIds[1] = 50;
        teamIds[2] = 2;

        vm.prank(admin);
        resolver.configureMarket(marketId, 14, WorldCupViewerParimutuelResolver.QueryType.MatchResult, teamIds);
        viewer.setMatchResult(14, false, 0, "");

        vm.warp(block.timestamp + 2 days);
        vm.prank(keeper);
        vm.expectRevert(WorldCupViewerParimutuelResolver.ViewerResultPending.selector);
        resolver.resolveMarket(marketId);
    }

    function _createMarket(uint8 outcomeCount) internal returns (uint256) {
        ParimutuelMarketConfig memory config = ParimutuelMarketConfig({
            tradingCloseTime: uint64(block.timestamp + 1 days),
            resolutionTime: uint64(block.timestamp + 2 days),
            outcomeCount: outcomeCount,
            resolverType: ParimutuelResolverType.Admin,
            fallbackResolverType: ParimutuelResolverType.Admin,
            curveType: ParimutuelCurveType.IndependentLog,
            curveParam: factory.INDEPENDENT_LOG_LIQUIDITY_RECOMMENDED(),
            feeBps: 0,
            metadataHash: keccak256("world-cup-strike-match"),
            metadataURI: "ipfs://world-cup-strike-match",
            resolverConfig: ""
        });

        vm.prank(admin);
        return factory.createMarket(config);
    }
}
