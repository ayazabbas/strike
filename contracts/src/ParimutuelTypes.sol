// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Lifecycle for parimutuel markets.
enum ParimutuelMarketState {
    Open,
    Closed,
    Resolving,
    Resolved,
    Invalid,
    Cancelled
}

/// @notice Supported resolution modes for parimutuel markets.
enum ParimutuelResolverType {
    Admin,
    AI,
    Pyth
}

/// @notice Candidate curve families for reward-share issuance.
enum ParimutuelCurveType {
    Flat,
    PiecewiseBand,
    IndependentLog
}

/// @notice Market creation parameters for parimutuel markets.
struct ParimutuelMarketConfig {
    uint64 closeTime;
    uint8 outcomeCount;
    ParimutuelResolverType resolverType;
    ParimutuelResolverType fallbackResolverType;
    ParimutuelCurveType curveType;
    uint128 curveParam;
    uint16 feeBps;
    bytes32 metadataHash;
    string metadataURI;
    bytes resolverConfig;
}

/// @notice Stored parimutuel market metadata.
struct ParimutuelMarket {
    uint256 marketId;
    address creator;
    uint64 closeTime;
    uint8 outcomeCount;
    ParimutuelMarketState state;
    ParimutuelResolverType resolverType;
    ParimutuelResolverType fallbackResolverType;
    ParimutuelCurveType curveType;
    uint128 curveParam;
    uint16 feeBps;
    uint8 winningOutcomeId;
    bool hasWinner;
    bool adminFallbackActivated;
    bytes32 metadataHash;
    string metadataURI;
    bytes resolverConfig;
}

/// @notice Constant-rate issuance interval for piecewise reward-share pricing.
struct ParimutuelPiecewiseBand {
    uint256 upperBound;
    uint32 rateBps;
}

/// @notice Aggregate pool state for one market outcome.
struct ParimutuelOutcomePool {
    uint256 principal;
    uint256 rewardShares;
}

/// @notice Per-user state for one market outcome.
struct ParimutuelPosition {
    uint256 principal;
    uint256 rewardShares;
}

/// @notice Atomic buy instruction for a parimutuel market.
struct ParimutuelBuyParam {
    uint8 outcomeId;
    uint256 amountIn;
}
