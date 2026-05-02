# Parimutuel Pool Markets

Parimutuel markets are Strike's pool-based prediction market format. They sit alongside the FBA orderbook: orderbook markets are best for actively traded binary outcomes, while parimutuel pools are best for multi-choice events, longer-running questions, and markets where users want simple buy-and-hold exposure without managing limit orders.

## What They Are

A parimutuel market has **2–8 outcomes**. Traders choose an outcome and buy into that outcome's pool with USDT. There is no orderbook and no selling/cashout in V1 — positions are internal, non-transferable claims on the final pool.

When the market resolves, the winning side receives:

1. their own winning principal back, plus
2. a proportional share of the losing outcome pools.

Losing outcomes pay nothing. If a market is invalid or cancelled, users can refund their principal.

## Orderbook vs. Parimutuel

| Feature | FBA Orderbook Markets | Parimutuel Pool Markets |
|---------|------------------------|--------------------------|
| Best for | Liquid binary markets and active trading | Multi-choice events and simple directional exposure |
| Outcomes | Binary UP/DOWN or YES/NO | 2–8 named outcomes |
| Pricing | Limit-order price discovery, $0.01–$0.99 ticks | Pool-implied probabilities from current liquidity |
| Execution | Periodic batch auctions at a uniform clearing price | Immediate buy into the selected outcome pool |
| Position management | Can sell before expiry through the orderbook | Buy-and-hold until claim/refund |
| Resolution | Pyth, AI, or admin fallback depending on market | Admin, AI, or Pyth with admin fallback |
| Payout | Winning positions redeem fixed value per lot | Winners split losing pools pro-rata |

Both systems are fully collateralized with USDT and settle through on-chain contracts.

## Market Timing

Parimutuel V2 separates the betting cutoff from the event timestamp:

- **Trading close time** — the last time users can buy into the pools.
- **Resolution time** — the event/reference timestamp used by the resolver.

This matters for markets where betting should close before the event concludes. For example, a sports market can stop accepting buys at kickoff but resolve after full time.

The contracts enforce `resolutionTime >= tradingCloseTime`. Buying and pool closing use `tradingCloseTime`; admin, AI, and Pyth resolution paths use `resolutionTime`.

## Resolution Modes

### Admin

The market creator/admin resolves to the winning outcome or marks the market invalid. This is useful for controlled internal markets and events that require human judgment.

### AI

The Parimutuel AI resolver sends a configured prompt to the Flap AI Oracle. The AI proposes the winning outcome, then a challenge/finality flow allows review before finalization. If the AI path fails or is challenged, the market can fall back to admin resolution.

### Pyth

The Parimutuel Pyth resolver uses a Pyth price feed at the market's `resolutionTime` and maps price thresholds to outcomes. This supports price-range markets such as "Where will BTC/USD be at 12:00 UTC?" with multiple buckets.

## Pool Pricing

Strike uses bounded curve presets to turn pool balances into displayed probabilities and projected payouts. The default recommended curve is the independent-log preset with `L = 40,000 USDT`; a more conservative `L = 100,000 USDT` preset is also supported.

The frontend shows:

- each outcome's current pool size,
- implied probability,
- projected payout for a new buy,
- total pool size,
- user's positions and claim/refund state.

## Lifecycle

1. **Created** — outcomes, resolver mode, trading close time, resolution time, fee, and curve are configured.
2. **Open** — users buy into outcome pools until `tradingCloseTime`.
3. **Closed** — no more buys; the market waits for `resolutionTime`.
4. **Resolving** — AI/Pyth/admin resolution is requested or submitted.
5. **Resolved** — winning outcome is final; winners can claim.
6. **Invalid/Cancelled** — users can refund principal.

## Contracts

The parimutuel stack is separate from the orderbook stack:

- `ParimutuelFactory` — creates markets and coordinates lifecycle/resolution.
- `ParimutuelPoolManager` — handles buys, pool accounting, and curve math.
- `ParimutuelVault` — holds USDT collateral for pool markets.
- `ParimutuelRedemption` — claims winning payouts and refunds invalid markets.
- `ParimutuelAIResolver` — Flap AI Oracle integration and challenge/finality flow.
- `ParimutuelPythResolver` — Pyth price-threshold resolution.

See [Deployments](../contracts/deployments.md) for live addresses.
