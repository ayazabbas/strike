# What is Strike?

**Strike** is a fully on-chain prediction market protocol on BNB Chain — live now at [app.strike.pm](https://app.strike.pm). Strike supports live market surfaces including **FBA orderbook markets** for active binary trading, **standard parimutuel pool markets** for simple multi-outcome predictions, **[Flap Token Pools](getting-started/flap-token-pools.md)** for creator-launched AI-resolved token pools backed by BEP20 collateral, and **[World Cup Markets](getting-started/world-cup.md)** for campaign-style USDT prediction pools.

Orderbook markets use a **Frequent Batch Auction (FBA) CLOB** where orders are collected and cleared at uniform prices in periodic batches. This gives traders real price discovery, limit orders, and fair execution without the MEV problems of continuous orderbooks.

Parimutuel pool markets let users back one of 2–8 outcomes directly from a pooled interface. There is no orderbook to manage: users buy into an outcome pool, then winners split the losing pools pro-rata after resolution. [Flap Token Pools](getting-started/flap-token-pools.md) extend this pool model to creator-launched token markets with external BEP20 collateral and FLAP AI resolution. [World Cup Markets](getting-started/world-cup.md) use a campaign-focused USDT experience with wallet USDT, bonus credit, early-pick incentives, and KOL signal icons where configured.

Markets can resolve through **Pyth Network** price feeds, the **Flap AI Oracle**, or admin fallback depending on the market type and configuration.

## Core Properties

- **Live market engines** — FBA orderbook markets, standard parimutuel pools, and [Flap Token Pools](getting-started/flap-token-pools.md) are live on BNB Chain
- **On-chain orderbook** — all order placement, matching, and settlement happen on BNB Chain smart contracts
- **Batch auction clearing** — orderbook markets match at a single uniform clearing price per batch, with pro-rata fills on the oversubscribed side
- **Parimutuel pools** — 2–8 outcome markets where winners receive principal back plus a proportional share of losing pools
- **Split pool timing** — parimutuel markets support separate `tradingCloseTime` and `resolutionTime`, so betting can close before the event resolves
- **Multiple collateral types** — orderbook markets use USDT; standard pools use USDT or STRIKE; Flap Token Pools can use creator-selected BEP20 collateral
- **Pyth + FLAP AI resolution** — deterministic price-feed markets, admin-resolved pools, and AI-resolved pools are supported, with challenge/fallback paths where configured
- **Atomic orderbook settlement** — `clearBatch(marketId)` clears an orderbook batch and settles all orders inline in a single transaction
- **Uniform fees** — orderbook trades use 20 bps filled-collateral fees; pool markets use configured protocol fees

## Architecture at a Glance

```
Orderbook traders ──→ OrderBook ──→ BatchAuction (atomic clear + settle)
                         │                       │
                    Vault (USDT escrow)    Positions (internal)
                         │                       │
                  MarketFactory ◄── PythResolver / AIResolver ──→ Redemption

Pool traders ─────→ ParimutuelPoolManager ──→ ParimutuelVault
                         │                           │
                  ParimutuelFactory ◄── AI/Pyth/Admin resolution ──→ ParimutuelRedemption

Flap pool creators/traders ─→ NativeTokenPoolManager ─→ NativeTokenPoolVault
                         │                                  │
          NativeTokenParimutuelFactory ◄── NativeTokenPoolAIResolver ─→ NativeTokenPoolRedemption

Off-chain (non-authoritative):
  • Keepers (clear batches, close pools, resolve markets)
  • Indexer + API (orderbook snapshots, pool state, trade history, WebSocket)
  • Web Frontend (orderbook terminal + pool market interface)
```

## Links

- **App:** [app.strike.pm](https://app.strike.pm)
- **Docs:** [docs.strike.pm](https://docs.strike.pm)
- **Chain:** BNB Chain (BSC)
- **Oracle:** [Pyth Network](https://pyth.network/)
