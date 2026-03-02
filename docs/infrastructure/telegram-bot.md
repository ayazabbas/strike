# Telegram Bot

Strike's Telegram bot provides a lightweight trading interface and notifications. For advanced trading (full orderbook, charts, bulk operations), use the web frontend.

## Features

- **Embedded wallets** — Privy server wallets created on `/start`, no seed phrases
- **Quick trading** — place limit orders via inline buttons
- **Orderbook preview** — top 3 bids/asks displayed in-chat
- **Notifications** — batch fills, market resolution, position outcomes
- **Wallet management** — deposit, withdraw, check balance

## Commands

| Command | Description |
|---------|-------------|
| `/start` | Create wallet, show main menu |
| `/markets` | Browse active markets |
| `/orders` | View open orders |
| `/portfolio` | Positions and P&L |
| `/wallet` | Balance and address |
| `/help` | How to use Strike |

## Architecture

```
grammY (TypeScript) → viem (BSC RPC) → Strike contracts
                    → Privy API (wallets)
                    → Indexer API (market data)
                    → SQLite (user state)
```

## Limitations vs Web Frontend

The bot is intentionally simple. For full functionality, it links to the web frontend:

| Feature | Bot | Web |
|---------|-----|-----|
| Place limit orders | ✅ (basic) | ✅ (full) |
| View orderbook | Top 3 levels | Full depth + chart |
| Order types | Limit only | Limit, Post-Only, IOC, Batch-Only |
| Bulk operations | ❌ | ✅ |
| Price charts | ❌ | ✅ |
| Portfolio analytics | Basic | Full P&L history |
