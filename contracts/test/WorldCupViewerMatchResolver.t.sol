// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/USDTParimutuelV3Factory.sol";
import "../src/USDTParimutuelV3Types.sol";
import "../src/WorldCupViewerMatchResolver.sol";

contract MockWorldCupViewer {
    struct MatchViewResult {
        uint256 matchId;
        string matchName;
        bool isResolved;
        uint256 teamId;
        string teamName;
    }

    mapping(uint256 => MatchViewResult) internal _matchResults;
    mapping(uint256 => MatchViewResult) internal _groupResults;
    MatchViewResult internal _winnerResult;

    function setMatchResult(uint256 matchId, bool isResolved, uint256 teamId, string calldata teamName) external {
        _matchResults[matchId] = MatchViewResult({
            matchId: matchId, matchName: "match", isResolved: isResolved, teamId: teamId, teamName: teamName
        });
    }

    function setGroupResult(uint256 matchId, bool isResolved, uint256 teamId, string calldata teamName) external {
        _groupResults[matchId] = MatchViewResult({
            matchId: matchId, matchName: "group", isResolved: isResolved, teamId: teamId, teamName: teamName
        });
    }

    function setWorldCupWinner(bool isResolved, uint256 teamId, string calldata teamName) external {
        _winnerResult = MatchViewResult({
            matchId: 1, matchName: "winner", isResolved: isResolved, teamId: teamId, teamName: teamName
        });
    }

    function getMatchResult(uint256 matchId) external view returns (MatchViewResult memory) {
        return _matchResults[matchId];
    }

    function getGroupMatchWinners(uint256 matchId) external view returns (MatchViewResult memory) {
        return _groupResults[matchId];
    }

    function getWorldCupWinner() external view returns (MatchViewResult memory) {
        return _winnerResult;
    }
}

contract WorldCupViewerMatchResolverTest is Test {
    address internal admin = address(0xA11CE);
    address internal keeper = address(0xB0B);

    USDTParimutuelV3Factory internal factory;
    MockWorldCupViewer internal viewer;
    WorldCupViewerMatchResolver internal resolver;

    function setUp() public {
        factory = new USDTParimutuelV3Factory(admin);
        viewer = new MockWorldCupViewer();
        resolver = new WorldCupViewerMatchResolver(admin, address(factory), address(viewer));

        bytes32 factoryAdminRole = factory.ADMIN_ROLE();
        bytes32 keeperRole = resolver.KEEPER_ROLE();

        vm.prank(admin);
        factory.grantRole(factoryAdminRole, address(resolver));
        vm.prank(admin);
        resolver.grantRole(keeperRole, keeper);
    }

    function test_resolveGroupStageMatchMapsViewerTeamIdToOutcome() public {
        uint256 marketId = _createMarket(3);
        uint256[] memory teamIds = new uint256[](3);
        teamIds[0] = 1; // Mexico
        teamIds[1] = 50; // draw
        teamIds[2] = 2; // South Africa

        vm.prank(admin);
        resolver.configureMarket(marketId, 14, WorldCupViewerMatchResolver.QueryType.MatchResult, teamIds);
        viewer.setMatchResult(14, true, 50, "draw");

        vm.warp(block.timestamp + 2 days);
        vm.prank(keeper);
        resolver.resolveMarket(marketId);

        USDTParimutuelV3Market memory market = factory.getMarket(marketId);
        assertEq(uint8(market.state), uint8(USDTParimutuelV3MarketState.Resolved));
        assertEq(market.winningOutcomeId, 1);
        assertTrue(market.hasWinner);
    }

    function test_resolveGroupWinnerUsesGroupViewerMethod() public {
        uint256 marketId = _createMarket(4);
        uint256[] memory teamIds = new uint256[](4);
        teamIds[0] = 1;
        teamIds[1] = 2;
        teamIds[2] = 3;
        teamIds[3] = 4;

        vm.prank(admin);
        resolver.configureMarket(marketId, 2, WorldCupViewerMatchResolver.QueryType.GroupWinner, teamIds);
        viewer.setGroupResult(2, true, 3, "South Korea");

        vm.warp(block.timestamp + 2 days);
        vm.prank(keeper);
        resolver.resolveMarket(marketId);

        USDTParimutuelV3Market memory market = factory.getMarket(marketId);
        assertEq(uint8(market.state), uint8(USDTParimutuelV3MarketState.Resolved));
        assertEq(market.winningOutcomeId, 2);
    }

    function test_resolveWorldCupWinnerUsesWinnerViewerMethod() public {
        uint256 marketId = _createMarket(3);
        uint256[] memory teamIds = new uint256[](3);
        teamIds[0] = 29;
        teamIds[1] = 33;
        teamIds[2] = 49;

        vm.prank(admin);
        resolver.configureMarket(marketId, 1, WorldCupViewerMatchResolver.QueryType.WorldCupWinner, teamIds);
        viewer.setWorldCupWinner(true, 49, "others");

        vm.warp(block.timestamp + 2 days);
        vm.prank(keeper);
        resolver.resolveMarket(marketId);

        USDTParimutuelV3Market memory market = factory.getMarket(marketId);
        assertEq(uint8(market.state), uint8(USDTParimutuelV3MarketState.Resolved));
        assertEq(market.winningOutcomeId, 2);
    }

    function test_revertsWhenViewerResultIsPending() public {
        uint256 marketId = _createMarket(3);
        uint256[] memory teamIds = new uint256[](3);
        teamIds[0] = 1;
        teamIds[1] = 50;
        teamIds[2] = 2;

        vm.prank(admin);
        resolver.configureMarket(marketId, 14, WorldCupViewerMatchResolver.QueryType.MatchResult, teamIds);
        viewer.setMatchResult(14, false, 0, "");

        vm.warp(block.timestamp + 2 days);
        vm.prank(keeper);
        vm.expectRevert(WorldCupViewerMatchResolver.ViewerResultPending.selector);
        resolver.resolveMarket(marketId);
    }

    function test_revertsWhenViewerTeamIdIsNotConfiguredForMarket() public {
        uint256 marketId = _createMarket(3);
        uint256[] memory teamIds = new uint256[](3);
        teamIds[0] = 1;
        teamIds[1] = 50;
        teamIds[2] = 2;

        vm.prank(admin);
        resolver.configureMarket(marketId, 14, WorldCupViewerMatchResolver.QueryType.MatchResult, teamIds);
        viewer.setMatchResult(14, true, 9, "Brazil");

        vm.warp(block.timestamp + 2 days);
        vm.prank(keeper);
        vm.expectRevert(WorldCupViewerMatchResolver.UnmappedViewerTeam.selector);
        resolver.resolveMarket(marketId);
    }

    function _createMarket(uint8 outcomeCount) internal returns (uint256) {
        USDTParimutuelV3MarketConfig memory config = USDTParimutuelV3MarketConfig({
            tradingCloseTime: uint64(block.timestamp + 1 days),
            resolutionTime: uint64(block.timestamp + 2 days),
            outcomeCount: outcomeCount,
            feeBps: 0,
            creditEventId: 0,
            creditEnabled: false,
            metadataHash: keccak256("world-cup-viewer-match"),
            metadataURI: "ipfs://world-cup-viewer-match"
        });

        vm.prank(admin);
        return factory.createMarket(config);
    }
}
