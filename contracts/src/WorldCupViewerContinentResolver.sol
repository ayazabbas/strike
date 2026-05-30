// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./USDTParimutuelV3Factory.sol";
import "./USDTParimutuelV3Types.sol";

interface IWorldCupWinnerViewer {
    struct MatchViewResult {
        uint256 matchId;
        string matchName;
        bool isResolved;
        uint256 teamId;
        string teamName;
    }

    function getWorldCupWinner() external view returns (MatchViewResult memory);
}

/// @title WorldCupViewerContinentResolver
/// @notice Resolves a World Cup continent-winner USDT parimutuel market from Flap's WorldCupViewer winner team.
/// @dev Grant this contract ADMIN_ROLE on USDTParimutuelV3Factory before keeper resolution.
contract WorldCupViewerContinentResolver is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    struct MarketConfig {
        bool configured;
        mapping(uint256 => uint8) continentOutcomeByTeamId;
    }

    USDTParimutuelV3Factory public immutable factory;
    IWorldCupWinnerViewer public immutable viewer;

    mapping(uint256 => MarketConfig) internal _marketConfigs;

    event MarketConfigured(uint256 indexed marketId, uint256[] teamIds, uint8[] outcomeIds);
    event MarketResolvedFromViewer(uint256 indexed marketId, uint256 indexed teamId, uint8 winningOutcomeId);

    error ZeroAddress();
    error EmptyMapping();
    error LengthMismatch();
    error InvalidOutcome();
    error MarketNotConfigured();
    error ViewerResultPending();
    error ViewerMatchIdMismatch();
    error UnmappedViewerTeam();

    constructor(address admin, address factory_, address viewer_) {
        if (admin == address(0) || factory_ == address(0) || viewer_ == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        factory = USDTParimutuelV3Factory(factory_);
        viewer = IWorldCupWinnerViewer(viewer_);
    }

    function configureMarket(uint256 marketId, uint256[] calldata teamIds, uint8[] calldata outcomeIds)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (teamIds.length == 0) revert EmptyMapping();
        if (teamIds.length != outcomeIds.length) revert LengthMismatch();

        USDTParimutuelV3Market memory market = factory.getMarket(marketId);
        MarketConfig storage config = _marketConfigs[marketId];
        config.configured = true;

        for (uint256 i = 0; i < teamIds.length; i++) {
            if (outcomeIds[i] >= market.outcomeCount) revert InvalidOutcome();
            config.continentOutcomeByTeamId[teamIds[i]] = outcomeIds[i] + 1;
        }

        emit MarketConfigured(marketId, teamIds, outcomeIds);
    }

    function resolveMarket(uint256 marketId) external onlyRole(KEEPER_ROLE) nonReentrant {
        MarketConfig storage config = _marketConfigs[marketId];
        if (!config.configured) revert MarketNotConfigured();

        IWorldCupWinnerViewer.MatchViewResult memory result = viewer.getWorldCupWinner();
        if (!result.isResolved) revert ViewerResultPending();
        if (result.matchId != 1) revert ViewerMatchIdMismatch();

        uint8 winningOutcomeId = _mapTeamIdToOutcome(config, result.teamId);
        factory.resolveToWinner(marketId, winningOutcomeId);

        emit MarketResolvedFromViewer(marketId, result.teamId, winningOutcomeId);
    }

    function previewResolution(uint256 marketId)
        external
        view
        returns (bool isResolved, uint256 teamId, string memory teamName, uint8 winningOutcomeId)
    {
        MarketConfig storage config = _marketConfigs[marketId];
        if (!config.configured) revert MarketNotConfigured();

        IWorldCupWinnerViewer.MatchViewResult memory result = viewer.getWorldCupWinner();
        if (!result.isResolved) {
            return (false, result.teamId, result.teamName, 0);
        }

        return (true, result.teamId, result.teamName, _mapTeamIdToOutcome(config, result.teamId));
    }

    function mappedOutcome(uint256 marketId, uint256 teamId) external view returns (bool mapped, uint8 outcomeId) {
        uint8 stored = _marketConfigs[marketId].continentOutcomeByTeamId[teamId];
        if (stored == 0) return (false, 0);
        return (true, stored - 1);
    }

    function _mapTeamIdToOutcome(MarketConfig storage config, uint256 teamId) internal view returns (uint8) {
        uint8 stored = config.continentOutcomeByTeamId[teamId];
        if (stored == 0) revert UnmappedViewerTeam();
        return stored - 1;
    }
}
