# MEV Mitigation

## The Problem

On continuous orderbooks, MEV bots exploit time priority: front-running, sandwiching, and racing to cancel stale orders. This extracts value from traders and undermines market fairness.

## How FBA Helps

Frequency Batch Auctions eliminate intra-batch time priority:

- **No front-running within a batch** — all orders in the same batch are treated equally
- **Uniform clearing price** — no sequential price impact from ordered fills
- **Maker protection** — makers have the full batch interval to cancel stale quotes before the next clearing

## Remaining MEV Vectors

FBA doesn't eliminate all MEV. Open on-chain order submission still leaks intent:

### Batch-Boundary Strategies
Sophisticated actors can observe pending orders in the mempool and submit orders just before a batch deadline. Multi-block batches (~3s) reduce this advantage compared to per-block clearing.

### Cancellation Races
Makers racing to cancel stale quotes before a batch clears. The batch interval gives makers time, The batch interval itself provides the primary protection against front-running.

### Resolution Observation
Near expiry, traders may observe Pyth price movements and attempt to front-run the final batch. **Mitigation:** trading halts when `timeRemaining < batchInterval` — no trading during the resolution-sensitive period.

## BNB Chain MEV Infrastructure

BNB Chain provides ecosystem-level MEV mitigation tools:

| Tool | Description |
|------|-------------|
| **BEP-322 Builder API** | Builder/validator separation for private transaction delivery |
| **NodeReal Bundle API** | Private, atomic transaction bundles (not propagated to P2P) |
| **Chainstack MEV Protection** | Routes transactions through builders, bypassing public mempool |

## Optional Private Submission

Strike supports an optional private submission path:

- **Default:** open on-chain submission (simplest, most composable)
- **Advanced:** route orders through MEV-protected RPC endpoints for privacy
- **Frontend toggle:** "Submit privately" option in the web interface
- **Graceful degradation:** protocol works identically regardless of submission method

This is an infrastructure-level feature, not a protocol-level guarantee. It depends on the availability and trust assumptions of the private transaction relays.
