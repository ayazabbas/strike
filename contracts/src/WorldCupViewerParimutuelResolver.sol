// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ParimutuelFactory.sol";
import "./ParimutuelTypes.sol";

interface IWorldCupViewerForParimutuel {
    struct MatchViewResult {
        uint256 matchId;
        string matchName;
        bool isResolved;
        uint256 teamId;
        string teamName;
    }

    function getWorldCupWinner() external view returns (MatchViewResult memory);
    function getGroupMatchWinners(uint256 matchId) external view returns (MatchViewResult memory);
    function getMatchResult(uint256 matchId) external view returns (MatchViewResult memory);
    function getTeamName(uint256 teamId) external view returns (string memory);
}

/// @title WorldCupViewerParimutuelResolver
/// @notice Resolves STRIKE/native parimutuel World Cup markets from Flap's WorldCupViewer read-only contract.
/// @dev Grant this contract ADMIN_ROLE on the target ParimutuelFactory before calling resolveMarket.
contract WorldCupViewerParimutuelResolver is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    enum QueryType {
        MatchResult,
        GroupWinner,
        WorldCupWinner
    }

    struct MarketConfig {
        bool configured;
        uint256 viewerMatchId;
        QueryType queryType;
        uint256[] teamIdsByOutcome;
    }

    ParimutuelFactory public immutable factory;
    IWorldCupViewerForParimutuel public immutable viewer;

    mapping(uint256 => MarketConfig) internal _marketConfigs;

    event MarketConfigured(
        uint256 indexed marketId, uint256 indexed viewerMatchId, QueryType queryType, uint256[] teamIdsByOutcome
    );
    event MarketResolvedFromViewer(
        uint256 indexed marketId, uint256 indexed viewerMatchId, uint256 teamId, uint8 winningOutcomeId
    );

    error ZeroAddress();
    error EmptyOutcomes();
    error OutcomeCountMismatch();
    error MarketNotConfigured();
    error ViewerResultPending();
    error UnmappedViewerTeam();
    error ViewerMatchIdMismatch();

    constructor(address admin, address factory_, address viewer_) {
        if (admin == address(0) || factory_ == address(0) || viewer_ == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        factory = ParimutuelFactory(factory_);
        viewer = IWorldCupViewerForParimutuel(viewer_);
    }

    function configureMarket(
        uint256 marketId,
        uint256 viewerMatchId,
        QueryType queryType,
        uint256[] calldata teamIdsByOutcome
    ) external onlyRole(ADMIN_ROLE) {
        if (teamIdsByOutcome.length == 0) revert EmptyOutcomes();

        ParimutuelMarket memory market = factory.getMarket(marketId);
        if (teamIdsByOutcome.length != market.outcomeCount) revert OutcomeCountMismatch();

        MarketConfig storage config = _marketConfigs[marketId];
        config.configured = true;
        config.viewerMatchId = viewerMatchId;
        config.queryType = queryType;
        config.teamIdsByOutcome = teamIdsByOutcome;

        emit MarketConfigured(marketId, viewerMatchId, queryType, teamIdsByOutcome);
    }

    function resolveMarket(uint256 marketId) external onlyRole(KEEPER_ROLE) nonReentrant {
        MarketConfig storage config = _marketConfigs[marketId];
        if (!config.configured) revert MarketNotConfigured();

        IWorldCupViewerForParimutuel.MatchViewResult memory result =
            _readViewerResult(config.viewerMatchId, config.queryType);
        if (!result.isResolved) revert ViewerResultPending();
        if (result.matchId != config.viewerMatchId) revert ViewerMatchIdMismatch();

        uint8 winningOutcomeId = _mapTeamIdToOutcome(config, result.teamId);

        ParimutuelMarket memory market = factory.getMarket(marketId);
        if (market.state == ParimutuelMarketState.Open) {
            factory.closeMarket(marketId);
        }
        factory.resolveToWinner(marketId, winningOutcomeId);

        emit MarketResolvedFromViewer(marketId, config.viewerMatchId, result.teamId, winningOutcomeId);
    }

    function getMarketConfig(uint256 marketId)
        external
        view
        returns (bool configured, uint256 viewerMatchId, QueryType queryType, uint256[] memory teamIdsByOutcome)
    {
        MarketConfig storage config = _marketConfigs[marketId];
        return (config.configured, config.viewerMatchId, config.queryType, config.teamIdsByOutcome);
    }

    function previewResolution(uint256 marketId)
        external
        view
        returns (bool isResolved, uint256 teamId, string memory teamName, uint8 winningOutcomeId)
    {
        MarketConfig storage config = _marketConfigs[marketId];
        if (!config.configured) revert MarketNotConfigured();

        IWorldCupViewerForParimutuel.MatchViewResult memory result =
            _readViewerResult(config.viewerMatchId, config.queryType);
        if (!result.isResolved) {
            return (false, result.teamId, result.teamName, 0);
        }

        return (true, result.teamId, result.teamName, _mapTeamIdToOutcome(config, result.teamId));
    }

    function _readViewerResult(uint256 viewerMatchId, QueryType queryType)
        internal
        view
        returns (IWorldCupViewerForParimutuel.MatchViewResult memory)
    {
        if (queryType == QueryType.WorldCupWinner) {
            return viewer.getWorldCupWinner();
        }
        if (queryType == QueryType.GroupWinner) {
            return viewer.getGroupMatchWinners(viewerMatchId);
        }
        return viewer.getMatchResult(viewerMatchId);
    }

    function _mapTeamIdToOutcome(MarketConfig storage config, uint256 teamId) internal view returns (uint8) {
        uint256 length = config.teamIdsByOutcome.length;
        for (uint256 i = 0; i < length; i++) {
            if (config.teamIdsByOutcome[i] == teamId) {
                return uint8(i);
            }
        }
        revert UnmappedViewerTeam();
    }
}
