# Oracle Resolution

Strike supports two resolution methods: **Pyth Price Feeds** for price-based markets and the **Flap AI Oracle** for question-based markets. This page covers both.

## Resolution Methods

| Method | Used For | Source |
|--------|----------|--------|
| **Pyth Price Feeds** | Price markets ("Will BTC be above $X?") | Cryptographically signed price data |
| **Flap AI Oracle** | AI markets ("Will the Fed cut rates?") | LLM reasoning with IPFS proof |

---

## Pyth Price Feed Resolution

Price markets are resolved by Pyth Network oracle price feeds. No human intervention, no subjective arbitration, no governance votes.

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

---

## AI Oracle Resolution

AI markets are resolved by the **Flap AI Oracle**, which uses large language models to evaluate question-based prompts. The `AIResolver` contract manages the full lifecycle:

1. **Request** — At market expiry, a keeper calls `resolveMarket()` which sends the prompt to the oracle
2. **LLM reasoning** (~90 seconds) — The oracle backend feeds the prompt to the selected model, which reasons over the question using current information
3. **Callback** — The oracle calls back with a binary choice (0 = YES, 1 = NO)
4. **Liveness window** (5 minutes) — The proposed resolution can be challenged
5. **Finalisation** — If unchallenged, anyone calls `finalise()` to settle the market

### Challenge Mechanism

During the 5-minute liveness window, anyone can challenge the AI's proposed outcome by posting a 0.1 BNB bond. This extends the window to 24 hours for admin review. The admin either confirms the original resolution (challenger loses bond) or overrides it (challenger gets bond + 0.01 BNB reward).

### IPFS Verification

Every AI resolution produces an IPFS proof containing the full prompt, reasoning trace, tool calls, and model metadata. The CID is available via the indexer API or on-chain via `FlapAIProvider.getRequest(requestId)`.

For full details, see [AI Markets](ai-markets.md).
