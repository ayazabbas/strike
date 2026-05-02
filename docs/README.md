# What is Strike?

**Strike** is a fully on-chain prediction market protocol on BNB Chain — live now at [app.strike.pm](https://app.strike.pm). Strike supports two first-class market formats: **FBA orderbook markets** for active binary trading and **parimutuel pool markets** for simple multi-outcome predictions.

Orderbook markets use a **Frequent Batch Auction (FBA) CLOB** where orders are collected and cleared at uniform prices in periodic batches. This gives traders real price discovery, limit orders, and fair execution without the MEV problems of continuous orderbooks.

Parimutuel pool markets let users back one of 2–8 outcomes directly from a pooled interface. There is no orderbook to manage: users buy into an outcome pool, then winners split the losing pools pro-rata after resolution.

Markets can resolve through **Pyth Network** price feeds, the **Flap AI Oracle**, or admin fallback depending on the market type and configuration.

## Core Properties

- **Two market engines** — FBA orderbook markets and parimutuel pool markets are both live, fully on-chain primitives
- **On-chain orderbook** — all order placement, matching, and settlement happen on BNB Chain smart contracts
- **Batch auction clearing** — orderbook markets match at a single uniform clearing price per batch, with pro-rata fills on the oversubscribed side
- **Parimutuel pools** — 2–8 outcome markets where winners receive principal back plus a proportional share of losing pools
- **Split pool timing** — parimutuel markets support separate `tradingCloseTime` and `resolutionTime`, so betting can close before the event resolves
- **USDT collateral** — positions are fully backed by USDT held in protocol vaults
- **Pyth + AI resolution** — deterministic price-feed markets and AI-resolved markets are both supported, with admin fallback where configured
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
