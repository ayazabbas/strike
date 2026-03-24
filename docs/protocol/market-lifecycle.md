# Market Lifecycle

Every Strike market transitions through these states:

```
Open → Closed → Resolving → Resolved
                          ↘ Cancelled
```

## States

### Open
- Orderbook accepts orders (place, cancel)
- Batch clearing runs at configured intervals (60s default)
- **Transition:** automatically enters `Closed` when `block.timestamp + batchInterval >= expiryTime`

### Closed
- **No new orders accepted** — the final batch has cleared
- Existing orders can still be cancelled (to free collateral)
- **Transition:** anyone submits a valid Pyth resolution via `resolve()` → enters `Resolving`

### Resolving
- Resolution has been submitted with signed Pyth price data
- **Finality gate:** the protocol waits for a 90-second finality period (`FINALITY_PERIOD = 90 seconds`) before finalizing
- **Challenge window:** during this period, anyone can submit an alternative Pyth update that would **change the outcome**; the contract deterministically picks the earliest valid `publishTime` within the settlement window
- **Transition:** `finalizeResolution()` called after finality window → enters `Resolved`

### Resolved
- Outcome is final (UP or DOWN)
- Winning positions pay out automatically at $0.01 per lot
- Losing positions are worthless

### Cancelled
- Triggered if no valid Pyth update is submitted within the maximum resolution window (24h)
- Also triggered if confidence interval exceeds threshold at resolution time
- All collateral is refunded

## Admin Fallback

The admin can call `setResolved()` as a fallback to skip the 2-step resolve/finalize process. This is intended for emergency situations only (e.g., Pyth feed failure, stuck resolution).

## Timeline (5-minute market, 60s batch interval)

```
0:00    Market created, strike price captured from Pyth
0:00    Orderbook open — batches clear every 60s
        ...
4:00    Last batch clears (< 60s remaining → trading halts)
5:00    Expiry timestamp reached — market enters Closed
5:00+   Resolver submits Pyth update for [T, T+60s] window → resolve()
        Finality period (90 seconds)
        Challenge window open during finality period
~6:30   finalizeResolution() → market Resolved
6:30+   Winning positions settled automatically
```
