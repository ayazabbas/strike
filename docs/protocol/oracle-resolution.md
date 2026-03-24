# Oracle Resolution

Strike markets are resolved exclusively by **Pyth Network** oracle price feeds. No human intervention, no subjective arbitration, no governance votes.

## Settlement Rule

Each market has an expiry timestamp `T`. Resolution uses the **earliest Pyth price update with `publishTime` in `[T, T+Δ]`**, where `Δ` is a protocol parameter (default: 60 seconds).

- The resolver fetches signed update data from Pyth's Hermes historical API
- The contract verifies it on-chain using `parsePriceFeedUpdates(updateData, priceId, T, T+Δ)`
- Pyth returns the update matching the window, and challengers can submit earlier `publishTime` updates to replace it
- The `price` field is used for settlement (not `ema_price`) — spot price for clean market semantics

## Confidence Interval Check

Pyth publishes a **confidence interval** with every price update. If the confidence is too wide relative to the price, the resolution is rejected:

```
Reject if: conf > confThresholdBps × |price| / 10000
```

Default threshold: 1% (100 bps). This prevents settlement on unreliable price data.

## Fallback Windows

If no Pyth update exists within `[T, T+Δ]`:
- The resolver can try `[T, T+2Δ]`, then `[T, T+3Δ]`, up to `K×Δ`
- This handles rare cases where Pyth publishing is delayed
- If no valid update exists within the maximum window → market cancels

## Finality Gate

Resolution is not instant:
1. Resolver calls `resolve()` with a Pyth update → `pendingResolution` is set, market enters `Resolving`
2. Protocol waits for a **90-second finality period** (`FINALITY_PERIOD = 90 seconds`)
3. During this window, anyone can submit an **alternative** Pyth update with an earlier valid `publishTime`, but only if it would **change the outcome** (e.g., flip the result from UP to DOWN)
4. After the finality window, `finalizeResolution()` is called → market enters `Resolved` state
5. **Admin fallback:** the admin can call `setResolved()` to skip the 2-step process in emergency situations

This "procedural challenge" mechanism ensures the deterministic rule (earliest update wins) is enforced even if the first resolver submits a suboptimal update.

## Resolver Incentives

- Resolution is **permissionless** — anyone can call `resolveMarket()`
- The protocol runs backstop keepers to ensure timely resolution
- If no one resolves within 24 hours, the market auto-cancels and all funds are refunded

## Why Pyth?

- **Pull oracle** — no continuous on-chain price pushing needed; only one update at resolution time
- **~400ms update cadence** at the oracle network level
- **Cryptographic verification** — signed data is verified on-chain, not trusted from an EOA
- **Historical data available** — Hermes API serves signed updates for past timestamps
- **Low cost** — update fees are negligible on BSC (1 wei default)
