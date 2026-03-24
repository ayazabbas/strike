# What is Strike?

**Strike** is a fully on-chain prediction market protocol on BNB Chain — live now at [app.strike.pm](https://app.strike.pm). Traders trade binary outcomes on whether an asset's price will be above or below a strike price at expiry.

Unlike simple parimutuel pools, Strike uses a **Frequent Batch Auction (FBA) CLOB** — an orderbook where orders are collected and cleared at uniform prices in periodic batches. This gives traders real price discovery, limit orders, and fair execution without the MEV problems of continuous orderbooks.

All markets are resolved trustlessly by **Pyth Network** oracle price feeds. No human intervention, no subjective arbitration.

## Core Properties

- **On-chain orderbook** — all orders, matching, and settlement happen on BNB Chain smart contracts
- **Batch auction clearing** — orders are matched at a single uniform clearing price per batch, with pro-rata fills on the oversubscribed side
- **USDT collateral** — positions are fully backed by USDT held in the Vault contract
- **Binary outcomes** — UP/DOWN positions, fully collateralized
- **Pyth oracle resolution** — deterministic settlement using `parsePriceFeedUpdates` with cryptographic verification
- **Atomic settlement** — `clearBatch(marketId)` clears the batch and settles all orders inline in a single transaction. No separate claim step
- **Uniform fees** — 20 bps fee on filled collateral, no maker/taker distinction
- **Permissionless** — anyone can resolve markets and clear batches

## Architecture at a Glance

```
Traders ──→ OrderBook ──→ BatchAuction (atomic clear + settle)
                │                       │
           Vault (USDT escrow)    Positions (internal)
                │                       │
         MarketFactory ◄── PythResolver ──→ Redemption
                                │
                          Pyth Oracle (on-chain)

Off-chain (non-authoritative):
  • Keepers (clear batches, resolve markets)
  • Indexer + API (orderbook snapshots, trade history, WebSocket)
  • Web Frontend (full trading terminal)
```

## Links

- **App:** [app.strike.pm](https://app.strike.pm)
- **Docs:** [docs.strike.pm](https://docs.strike.pm)
- **Chain:** BNB Chain (BSC)
- **Oracle:** [Pyth Network](https://pyth.network/)
