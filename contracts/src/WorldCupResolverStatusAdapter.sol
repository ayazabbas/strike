// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IFlapWorldCupViewer {
    struct MatchViewResult {
        uint256 matchId;
        string matchName;
        bool isResolved;
        uint256 teamId;
        string teamName;
    }

    function getWorldCupWinner() external view returns (MatchViewResult memory result);
}

/// @notice Adapter from Flap's WorldCupViewer API to Strike's winner-market status API.
contract WorldCupResolverStatusAdapter {
    IFlapWorldCupViewer public immutable flapViewer;

    error InvalidOutcome();

    constructor(address flapViewer_) {
        if (flapViewer_ == address(0)) revert InvalidOutcome();
        flapViewer = IFlapWorldCupViewer(flapViewer_);
    }

    function getOutcomeStatus(uint8 outcomeId)
        external
        view
        returns (bool isReported, bool result, bool isFlagged)
    {
        if (outcomeId > 42) revert InvalidOutcome();

        IFlapWorldCupViewer.MatchViewResult memory winner = flapViewer.getWorldCupWinner();
        if (!winner.isResolved) return (false, false, false);

        uint256 teamId = _strikeOutcomeToFlapTeamId(outcomeId);
        if (teamId == 0) return (false, false, false);

        return (true, winner.teamId == teamId, false);
    }

    function _strikeOutcomeToFlapTeamId(uint8 outcomeId) internal pure returns (uint256) {
        if (outcomeId == 0) return 29; // Spain
        if (outcomeId == 1) return 33; // France
        if (outcomeId == 2) return 45; // England
        if (outcomeId == 3) return 37; // Argentina
        if (outcomeId == 4) return 9; // Brazil
        if (outcomeId == 5) return 41; // Portugal
        if (outcomeId == 6) return 17; // Germany
        if (outcomeId == 7) return 21; // Netherlands
        if (outcomeId == 8) return 36; // Norway
        if (outcomeId == 10) return 25; // Belgium
        if (outcomeId == 11) return 13; // USA
        if (outcomeId == 12) return 10; // Morocco
        if (outcomeId == 13) return 44; // Colombia
        if (outcomeId == 14) return 22; // Japan
        if (outcomeId == 15) return 32; // Uruguay
        if (outcomeId == 16) return 46; // Croatia
        if (outcomeId == 17) return 1; // Mexico
        if (outcomeId == 18) return 8; // Switzerland
        if (outcomeId == 19) return 20; // Ecuador
        if (outcomeId == 20) return 34; // Senegal
        if (outcomeId == 21) return 15; // Australia
        if (outcomeId == 22) return 5; // Canada
        if (outcomeId == 23) return 12; // Scotland
        if (outcomeId == 24) return 3; // South Korea
        if (outcomeId == 25) return 14; // Paraguay
        if (outcomeId == 26) return 19; // Ivory Coast
        if (outcomeId == 27) return 26; // Egypt
        if (outcomeId == 28) return 27; // Iran
        if (outcomeId == 29) return 47; // Ghana
        if (outcomeId == 30) return 38; // Algeria
        if (outcomeId == 31) return 24; // Tunisia
        if (outcomeId == 32) return 39; // Austria
        if (outcomeId == 33) return 28; // New Zealand
        if (outcomeId == 34) return 11; // Haiti
        if (outcomeId == 35) return 40; // Jordan
        if (outcomeId == 36) return 18; // Curacao
        if (outcomeId == 37) return 43; // Uzbekistan
        if (outcomeId == 38) return 2; // South Africa
        if (outcomeId == 39) return 30; // Cape Verde
        if (outcomeId == 40) return 7; // Qatar
        if (outcomeId == 41) return 31; // Saudi Arabia
        if (outcomeId == 42) return 49; // Others
        return 0;
    }
}
