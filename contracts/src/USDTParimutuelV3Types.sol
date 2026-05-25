// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

enum USDTParimutuelV3MarketState {
    Open,
    Closed,
    Resolved,
    Invalid,
    Cancelled
}

struct USDTParimutuelV3MarketConfig {
    uint64 tradingCloseTime;
    uint64 resolutionTime;
    uint8 outcomeCount;
    uint16 feeBps;
    uint256 creditEventId;
    bool creditEnabled;
    bytes32 metadataHash;
    string metadataURI;
}

struct USDTParimutuelV3Market {
    uint256 marketId;
    address creator;
    uint64 tradingCloseTime;
    uint64 resolutionTime;
    uint8 outcomeCount;
    uint16 feeBps;
    uint256 creditEventId;
    bool creditEnabled;
    USDTParimutuelV3MarketState state;
    uint8 winningOutcomeId;
    bool hasWinner;
    bytes32 metadataHash;
    string metadataURI;
}

struct USDTParimutuelV3OutcomePool {
    uint256 principal;
    uint256 rewardShares;
    uint256 realPrincipal;
    uint256 creditPrincipal;
    uint256 realRewardShares;
    uint256 creditRewardShares;
}

struct USDTParimutuelV3Position {
    uint256 principal;
    uint256 rewardShares;
}
