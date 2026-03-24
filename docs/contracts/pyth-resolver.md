# PythResolver.sol

Handles Pyth oracle integration for deterministic market resolution.

## `resolveMarket(marketId, updateData)`

1. Verifies market is in `Closed` state
2. Calls `parsePriceFeedUpdates(updateData, priceId, T, T+Δ)` on the Pyth contract
3. **Confidence check:** reverts if `conf > confThresholdBps × |price| / 10000`
4. Sets `pendingResolution` with the parsed price and publish time
5. Records resolver address for bounty payment

## `finalizeResolution(marketId)`

1. Verifies at least 90 seconds have passed since `resolveMarket` (FINALITY_PERIOD)
2. Checks if any challenger submitted a better (earlier) update during the window
3. Determines outcome: price > strike → YES wins; price ≤ strike → NO wins
4. Transitions market to `Resolved`
5. Pays resolver bounty

## Challenges

Challenges are handled within `resolveMarket()` itself. During the finality window, anyone can call `resolveMarket()` again with alternative Pyth update data that has an earlier `publishTime` within `[T, T+Δ]`. A challenge is only accepted if the new update would change the market outcome (i.e., flip the resolution from YES to NO or vice versa). If accepted, the new update replaces the pending resolution and the challenger becomes the new resolver (gets bounty). There is no separate `challengeResolution()` function.

## Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `Δ (delta)` | 60s | Settlement window after expiry |
| `maxDelta` | 300s (5×Δ) | Maximum fallback window |
| `confThresholdBps` | 100 (1%) | Max confidence/price ratio |
| `finalityPeriod` | 90s | Time to wait for finality |

## Admin Fallback: `setResolved()`

The admin can call `setResolved(factoryMarketId, outcomeYes, settlementPrice)` on MarketFactory to directly resolve a market, bypassing the 2-step resolve/finalize process. This is a safety fallback for cases where Pyth data is unavailable or the normal resolution flow is stuck.

## Admin Transfer

Two-step admin transfer: `setPendingAdmin(address)` → `acceptAdmin()`. Prevents accidental admin loss.

## Events

```solidity
event ResolutionSubmitted(uint256 indexed factoryMarketId, int64 price, uint256 publishTime, address indexed resolver);
event ResolutionChallenged(uint256 indexed factoryMarketId, int64 newPrice, uint256 newPublishTime, address indexed challenger);
event ResolutionFinalized(uint256 indexed factoryMarketId, int64 price, bool outcomeYes, address indexed finalizer);
```
