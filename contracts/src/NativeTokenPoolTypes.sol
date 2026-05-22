// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./ParimutuelTypes.sol";

/// @notice Common challenge/slash reason codes for Flap Token Pools.
enum NativeTokenPoolReason {
    None,
    BadResolution,
    BadPrompt,
    BadMetadata,
    OracleFailure,
    Fraud,
    Other
}

/// @notice V1 challenge lifecycle. Admin adjudicates opened challenges.
enum NativeTokenPoolChallengeStatus {
    None,
    Open,
    Successful,
    Failed
}

/// @notice Permissionless creation parameters for arbitrary ERC20/BEP20 Flap Token Pools.
struct NativeTokenPoolMarketConfig {
    address collateralToken;
    uint64 tradingCloseTime;
    uint64 resolutionTime;
    uint8 outcomeCount;
    ParimutuelCurveType curveType;
    uint128 curveParam;
    uint16 feeBps;
    uint256 minStake;
    uint256 maxStake;
    bytes32 metadataHash;
    string metadataURI;
    string prompt;
}

/// @notice Stored market metadata and lifecycle.
struct NativeTokenPoolMarket {
    uint256 marketId;
    address creator;
    address collateralToken;
    uint64 tradingCloseTime;
    uint64 resolutionTime;
    uint64 challengeDeadline;
    uint8 outcomeCount;
    ParimutuelMarketState state;
    ParimutuelCurveType curveType;
    uint128 curveParam;
    uint16 feeBps;
    uint256 minStake;
    uint256 maxStake;
    uint8 winningOutcomeId;
    bool hasWinner;
    bool finalized;
    bool creatorBondSettled;
    uint256 creatorBondAmount;
    bytes32 metadataHash;
    string metadataURI;
    string prompt;
}

/// @notice Per-market challenge state.
struct NativeTokenPoolChallenge {
    address challenger;
    NativeTokenPoolChallengeStatus status;
    NativeTokenPoolReason reason;
    bytes32 reasonHash;
    uint256 bondAmount;
}
