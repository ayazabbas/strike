# What is Strike?

**Strike** is a fully on-chain prediction market protocol on BNB Chain. Traders buy and sell binary outcome tokens on whether an asset's price will be above or below a strike price at expiry.

Unlike simple parimutuel pools, Strike uses a **Frequency Batch Auction (FBA) CLOB** — an orderbook where orders are collected and cleared at uniform prices every 60 seconds (configurable per market). This gives traders real price discovery, limit orders, and fair execution without the MEV problems of continuous orderbooks.

All markets are resolved trustlessly by **Pyth Network** oracle price feeds. No human intervention, no subjective arbitration.

## Core Properties

- **On-chain orderbook** — all orders, matching, and settlement happen on BNB Chain smart contracts
- **Batch auction clearing** — orders are matched at a single uniform price per batch, with pro-rata fills on the oversubscribed side
- **Binary outcome tokens** — ERC-1155 YES/NO tokens, fully collateralized, tradeable on the book
- **Pyth oracle resolution** — deterministic settlement using `parsePriceFeedUpdates` with cryptographic verification
- **Claim-based settlement** — fills are not written per-order during clearing; traders claim their pro-rata share afterward, keeping clearing gas-efficient
- **Permissionless** — anyone can resolve markets, prune expired orders, and clear batches

## Architecture at a Glance

```
Traders ──→ OrderBook ──→ BatchAuction ──→ ClaimSettlement
                │                               │
           Vault (collateral)            OutcomeToken (ERC-1155)
                │                               │
         MarketFactory ◄── PythResolver ──→ Redemption
                                │
                          Pyth Oracle (on-chain)

Off-chain (non-authoritative):
  • Keepers (clear batches, resolve markets, prune orders)
  • Indexer + API (orderbook snapshots, trade history, WebSocket)
  • Telegram Bot (lightweight trading + notifications)
  • Web Frontend (full trading terminal)
```

## Links

- **GitHub:** [ayazabbas/strike](https://github.com/ayazabbas/strike)
- **Chain:** BNB Chain (BSC)
- **Oracle:** [Pyth Network](https://pyth.network/)
