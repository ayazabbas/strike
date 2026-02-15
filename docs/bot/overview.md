# Telegram Bot Overview

Strike's primary interface is a Telegram bot. No website, no browser extension — just open the bot and start betting.

## Why a Bot?

Telegram bots with inline keyboards provide a fast, familiar interface for crypto users. Many popular trading tools (BananaGun, BonkBot, Maestro) use this pattern. Users don't need to install anything or connect a wallet extension.

## Architecture

```
┌──────────────────────────────────────────────┐
│              Strike Telegram Bot              │
│                                              │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  │
│  │ Handlers │  │ Services │  │  Database  │  │
│  │          │  │          │  │  (SQLite)  │  │
│  │ start    │  │ privy    │  │            │  │
│  │ markets  │  │ pyth     │  │ users      │  │
│  │ betting  │  │ blockchain│ │ bets       │  │
│  │ mybets   │  │ notifs   │  │ wallets    │  │
│  │ wallet   │  │          │  │            │  │
│  │ settings │  │          │  │            │  │
│  │ admin    │  │          │  │            │  │
│  │ help     │  │          │  │            │  │
│  └──────────┘  └──────────┘  └───────────┘  │
│                                              │
│  Framework: grammY (TypeScript)              │
└──────────────────────────────────────────────┘
```

## Embedded Wallets

When a user sends `/start`, the bot creates a **Privy server wallet** for them. This is a custodial wallet managed server-side — the user never needs to handle private keys or sign transactions manually.

**Flow:**
1. User sends `/start`
2. Bot calls Privy API to create an embedded wallet
3. Wallet address is stored in SQLite and shown to the user
4. User sends BNB to their wallet address
5. When placing bets, the bot signs and sends transactions on their behalf

This dramatically simplifies the UX — no MetaMask, no WalletConnect, no seed phrases.

## Services

| Service | Purpose |
|---------|---------|
| **Privy** | Wallet creation, transaction signing |
| **Pyth** | Live BTC/USD price feeds from Hermes API |
| **Blockchain** | Contract interactions via viem (bets, claims, market info) |
| **Notifications** | Alerts users when markets resolve |

## Database

SQLite stores:
- User records (Telegram ID → wallet address)
- Bet records (market, side, amount, status)
- Bot state and settings
