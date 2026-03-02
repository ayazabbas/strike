# PythResolver.sol

Handles Pyth oracle integration for deterministic market resolution.

## `resolveMarket(marketId, updateData)`

1. Verifies market is in `Closed` state
2. Calls `parsePriceFeedUpdatesUnique(updateData, priceId, T, T+Δ)` on the Pyth contract
3. **Confidence check:** reverts if `conf > confThresholdBps × |price| / 10000`
4. Sets `pendingResolution` with the parsed price and publish time
5. Records resolver address for bounty payment

## `finalizeResolution(marketId)`

1. Verifies at least n+2 blocks have passed since `resolveMarket` (finality gate)
2. Checks if any challenger submitted a better (earlier) update during the window
3. Determines outcome: price > strike → YES wins; price ≤ strike → NO wins
4. Transitions market to `Resolved`
5. Pays resolver bounty

## `challengeResolution(marketId, updateData)`

During the finality window:
1. Submit alternative Pyth update data
2. Contract verifies it's valid and has an earlier `publishTime` within `[T, T+Δ]`
3. If earlier, replaces the pending resolution
4. Challenger becomes the new resolver (gets bounty)

## Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `Δ (delta)` | 60s | Settlement window after expiry |
| `maxDelta` | 300s (5×Δ) | Maximum fallback window |
| `confThresholdBps` | 100 (1%) | Max confidence/price ratio |
| `finalityBlocks` | 3 | Blocks to wait for economic finality |
