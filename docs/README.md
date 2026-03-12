# What is Strike?

**Strike** is a fully on-chain prediction market protocol on BNB Chain. Traders buy and sell binary outcome tokens on whether an asset's price will be above or below a strike price at expiry.

Unlike simple parimutuel pools, Strike uses a **Frequency Batch Auction (FBA) CLOB** — an orderbook where orders are collected and cleared at uniform prices in periodic batches. This gives traders real price discovery, limit orders, and fair execution without the MEV problems of continuous orderbooks.

All markets are resolved trustlessly by **Pyth Network** oracle price feeds. No human intervention, no subjective arbitration.

## Core Properties

- **On-chain orderbook** — all orders, matching, and settlement happen on BNB Chain smart contracts
- **Batch auction clearing** — orders are matched at a single uniform clearing price per batch, with pro-rata fills on the oversubscribed side
- **USDT collateral** — 1 YES + 1 NO = 1 USDT. Users approve the Vault for ERC-20 transfers before placing orders
- **Binary outcome tokens** — ERC-1155 YES/NO tokens, fully collateralized, tradeable on the book
- **Pyth oracle resolution** — deterministic settlement using `parsePriceFeedUpdates` with cryptographic verification
- **Atomic settlement** — `clearBatch(marketId)` clears the batch and settles all orders inline in a single transaction. No separate claim step
- **Uniform fees** — 20 bps fee on filled collateral, no maker/taker distinction
- **Permissionless** — anyone can resolve markets and clear batches

## Architecture at a Glance

```
Traders ──→ OrderBook ──→ BatchAuction (atomic clear + settle)
                │                       │
           Vault (USDT escrow)    OutcomeToken (ERC-1155)
                │                       │
         MarketFactory ◄── PythResolver ──→ Redemption
                                │
                          Pyth Oracle (on-chain)

Off-chain (non-authoritative):
  • Keepers (clear batches, resolve markets)
  • Indexer + API (orderbook snapshots, trade history, WebSocket)
  • Telegram Bot (lightweight trading + notifications)
  • Web Frontend (full trading terminal)
```

## Links

- **GitHub:** [ayazabbas/strike](https://github.com/ayazabbas/strike)
- **Chain:** BNB Chain (BSC)
- **Oracle:** [Pyth Network](https://pyth.network/)
