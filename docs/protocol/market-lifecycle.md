# Market Lifecycle

Every Strike market transitions through these states:

```
Open → Closed → Resolving → Resolved
                          ↘ Cancelled
```

## States

### Open
- Orderbook accepts orders (place, cancel)
- Batch clearing runs at configured intervals (~3s)
- Traders can mint/merge outcome token pairs
- **Transition:** automatically enters `Closed` when `block.timestamp + batchInterval >= expiryTime`

### Closed
- **No new orders accepted** — the final batch has cleared
- Existing orders can still be cancelled (to free collateral)
- Traders can still claim unclaimed fills from previous batches
- Outcome token pair minting/merging still available
- **Transition:** anyone submits a valid Pyth resolution → enters `Resolving`

### Resolving
- Resolution has been submitted with signed Pyth price data
- **Finality gate:** the protocol waits for economic finality (n+2 blocks on BSC) before finalizing
- **Challenge window:** during this period, anyone can submit an alternative Pyth update; the contract deterministically picks the earliest valid `publishTime` within the settlement window
- **Transition:** `finalizeResolution()` called after finality window → enters `Resolved`

### Resolved
- Outcome is final (YES or NO)
- Winning outcome tokens redeem 1:1 for collateral
- Losing tokens are worthless
- Resolver receives bounty from market creation bond

### Cancelled
- Triggered if no valid Pyth update is submitted within the maximum resolution window (24h)
- Also triggered if confidence interval exceeds threshold at resolution time
- All outcome tokens can be burned for collateral refund (1 YES + 1 NO → 1 collateral)
- Market creation bond returned minus gas costs

## Timeline (5-minute market, 3s batch interval)

```
0:00    Market created, strike price captured from Pyth
0:00    Orderbook open — batches clear every ~3s
        ...
4:57    Last batch clears (< 3s remaining → trading halts)
5:00    Expiry timestamp reached — market enters Closed
5:00+   Resolver submits Pyth update for [T, T+60s] window
        Finality gate (n+2 blocks, ~1.1s)
        Challenge window open during finality period
~5:02   finalizeResolution() → market Resolved
5:02+   Traders redeem winning tokens
```
