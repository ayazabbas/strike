// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

enum WorldCupWinnerMarketState {
    Open,
    Closed,
    Resolved,
    Invalid
}

enum WorldCupRound {
    PreTournament,
    EarlyGroupStage,
    LateGroupStage,
    RoundOf32,
    RoundOf16,
    QuarterFinal,
    SemiFinal,
    FinalBuildUp
}

struct WorldCupOutcomePool {
    uint256 principal;
    uint256 rewardShares;
    uint256 realPrincipal;
    uint256 creditPrincipal;
    uint256 realRewardShares;
    uint256 creditRewardShares;
}

struct WorldCupPosition {
    uint256 principal;
    uint256 rewardShares;
}
