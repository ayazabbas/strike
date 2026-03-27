# AIResolver.sol

The `AIResolver` contract manages AI-resolved markets. It extends `FlapAIConsumerBase` to interact with the Flap AI Oracle and implements an optimistic resolution pattern with a liveness window and challenge mechanism.

## Overview

- Holds BNB oracle fees deposited at market creation
- Sends prompts to the Flap AI Oracle at market expiry
- Receives oracle callbacks with the LLM's binary choice
- Enforces a 5-minute liveness window before finalising
- Supports challenges with a 0.1 BNB bond and 24-hour admin review

## State

```solidity
mapping(uint256 => uint256) public requestToMarket;      // requestId => factoryMarketId
mapping(uint256 => AIMarketConfig) public aiMarkets;     // factoryMarketId => config
mapping(uint256 => ProposedResolution) public proposals; // factoryMarketId => proposal

uint256 public constant LIVENESS_PERIOD = 5 minutes;
uint256 public constant CHALLENGE_PERIOD = 24 hours;
uint256 public constant CHALLENGE_BOND = 0.1 ether;
uint256 public constant CHALLENGER_REWARD = 0.01 ether;
```

### AIMarketConfig

```solidity
struct AIMarketConfig {
    string prompt;
    uint8 modelId;
    uint256 oracleFee;  // BNB amount locked at creation
    bool pending;       // true while awaiting oracle callback
}
```

### ProposedResolution

```solidity
struct ProposedResolution {
    uint8 choice;          // 0 = YES, 1 = NO
    uint256 livenessEnd;   // timestamp when liveness expires
    address challenger;    // non-zero if challenged
    uint256 challengeEnd;  // 0 unless challenged
    bool finalized;
}
```

## Functions

| Function | Access | Description |
|----------|--------|-------------|
| `depositFee(uint256 marketId)` | `payable` | Called by MarketFactory at AI market creation. Stores the BNB oracle fee. |
| `resolveMarket(uint256 marketId)` | `KEEPER_ROLE` | Sends the prompt to the Flap AI Oracle with the deposited fee. |
| `challenge(uint256 marketId)` | `payable` (0.1 BNB) | Posts a challenge bond during the liveness window. Extends to 24h review. |
| `finalise(uint256 marketId)` | Anyone | Finalises resolution after liveness window with no challenge. Calls `factory.setResolved()`. |
| `confirmResolution(uint256 marketId)` | `admin` | Confirms original AI outcome after a challenge. Bond goes to treasury. |
| `overrideResolution(uint256 marketId, bool newOutcome)` | `admin` | Overrides AI outcome. Challenger gets bond + 0.01 BNB reward. |
| `withdraw()` | `admin` | Emergency BNB drain. |

### Internal (Oracle Callbacks)

| Function | Description |
|----------|-------------|
| `_fulfillReasoning(uint256 requestId, uint8 choice)` | Oracle callback. Records proposed resolution and starts liveness window. |
| `_onFlapAIRequestRefunded(uint256 requestId)` | Oracle refund callback. Resets pending flag so keeper can retry. |

## Events

```solidity
event AIResolutionRequested(uint256 indexed marketId, uint256 requestId);
event AIResolutionProposed(uint256 indexed marketId, uint256 requestId, uint8 choice, uint256 livenessEnd);
event AIResolutionChallenged(uint256 indexed marketId, address challenger, uint256 challengeEnd);
event AIResolutionConfirmed(uint256 indexed marketId, uint8 choice);
event AIResolutionOverridden(uint256 indexed marketId, uint8 oldChoice, bool newOutcome);
event AIResolutionRefunded(uint256 indexed marketId, uint256 requestId);
```

## Access Control

| Role | Granted To | Purpose |
|------|-----------|---------|
| `KEEPER_ROLE` | Keeper wallet | Call `resolveMarket()` at market expiry |
| `ADMIN_ROLE` on MarketFactory | AIResolver | Call `setResolved()` and `setResolving()` on the factory |
| `admin` (AIResolver) | Deployer / multisig | Confirm or override challenged resolutions |

## FlapAIConsumerBase Pattern

`AIResolver` inherits from `FlapAIConsumerBase`, which provides:

- `_getFlapAIProvider()` — returns the oracle provider address
- `reason{value}(modelId, prompt, numChoices)` — sends a reasoning request with BNB payment
- `_fulfillReasoning(requestId, choice)` — virtual callback, overridden by AIResolver
- `_onFlapAIRequestRefunded(requestId)` — virtual refund callback

The oracle responds in approximately 90 seconds. The `_fulfillReasoning` callback has ~1M gas forwarded, so it should only perform storage writes (no external calls).
