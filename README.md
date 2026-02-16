<p align="center">
  <img src="assets/strike-logo-with-text.svg" alt="Strike Logo" width="200" />
</p>

<h1 align="center">Strike — Prediction Markets on Telegram</h1>

<p align="center">
  Binary UP/DOWN prediction markets powered by Pyth oracle on BNB Chain, accessible through a Telegram bot.
</p>

[![Built for BNB Chain](https://img.shields.io/badge/Built%20for-BNB%20Chain-F0B90B?style=flat-square)](https://www.bnbchain.org/)
[![Powered by Pyth](https://img.shields.io/badge/Powered%20by-Pyth%20Network-6B48FF?style=flat-square)](https://pyth.network/)

## 🎯 What is Strike?

Strike is a **Telegram bot** that lets users bet on whether crypto prices will go **UP ⬆️** or **DOWN ⬇️** within a set timeframe. Think of it like a simplified, transparent, on-chain prediction market — right inside Telegram.

No website needed. No wallet extensions. Just open the bot, fund your wallet, and start predicting.

## ✨ Features

- **🤖 Telegram Bot Interface** — Trade with inline buttons, no web app needed (like BananaGun/BonkBot)
- **💰 Embedded Wallets** — Auto-created Privy wallets, fund with BNB and start betting instantly
- **📊 Live Prices** — Real-time BTC/USD prices from Pyth Network oracle
- **⏱️ Fast Rounds** — 5-minute prediction markets for quick-fire action
- **🏊 Parimutuel Pools** — Fair odds determined by the market, not a house edge
- **🔒 Fully On-Chain** — All bets, resolutions, and payouts happen on BNB Chain smart contracts
- **⚡ Gas Efficient** — EIP-1167 minimal proxy clones (~$0.01-0.03 per transaction on BSC)

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Telegram User                      │
│              (inline keyboard UI)                    │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│              Strike Telegram Bot                     │
│  ┌───────────┐ ┌──────────┐ ┌────────────────────┐  │
│  │  grammY   │ │  SQLite  │ │   Privy Wallets    │  │
│  │ (bot fw)  │ │  (users) │ │ (server-side keys) │  │
│  └───────────┘ └──────────┘ └────────────────────┘  │
│  ┌───────────────────┐ ┌─────────────────────────┐  │
│  │   Pyth Hermes     │ │     viem (BSC RPC)      │  │
│  │ (live prices+VAA) │ │  (contract interaction) │  │
│  └───────────────────┘ └─────────────────────────┘  │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│               BNB Chain (BSC)                        │
│  ┌─────────────────┐  ┌──────────────────────────┐  │
│  │ MarketFactory   │  │   Market (EIP-1167)      │  │
│  │ (clone factory) │──│  • bet(UP/DOWN)          │  │
│  │ (market registry│  │  • resolve(pythData)     │  │
│  │  + admin)       │  │  • claim() payouts       │  │
│  └─────────────────┘  └──────────────────────────┘  │
│  ┌─────────────────────────────────────────────────┐│
│  │          Pyth Oracle (on-chain)                  ││
│  │  BTC/USD price feed                              ││
│  └─────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────┘
```

## 🚀 User Flow

1. **`/start`** → Bot creates a Privy embedded wallet for you
2. **Fund wallet** → Send BNB to your wallet address
3. **Browse markets** → See active BTC/USD markets with live prices
4. **Place a bet** → Tap a market → Choose UP ⬆️ or DOWN ⬇️ → Select amount → Confirm
5. **Wait for resolution** → Market resolves automatically after 5 minutes
6. **Claim winnings** → If you predicted correctly, claim your share of the pool!

## 🛠️ Tech Stack

| Component | Technology |
|-----------|-----------|
| **Smart Contracts** | Solidity 0.8.25, Foundry, OpenZeppelin v5 |
| **Blockchain** | BNB Chain (BSC Testnet / Mainnet) |
| **Oracle** | Pyth Network (Hermes REST API + on-chain verification) |
| **Bot Framework** | grammY (TypeScript) |
| **Wallet** | Privy Server Wallets (embedded, custodial) |
| **Database** | SQLite (better-sqlite3) |
| **RPC** | viem |
| **Proxy Pattern** | EIP-1167 Minimal Proxy Clones |

## 📦 Project Structure

```
strike/
├── contracts/              # Foundry project
│   ├── src/
│   │   ├── Market.sol          # Core prediction market
│   │   └── MarketFactory.sol   # EIP-1167 clone factory
│   ├── test/
│   │   ├── Market.t.sol        # 37 market tests
│   │   └── MarketFactory.t.sol # 14 factory tests
│   └── script/
│       └── Deploy.s.sol        # BSC deployment script
├── bot/                    # Telegram bot
│   └── src/
│       ├── index.ts            # Bot entry point
│       ├── config.ts           # Environment config
│       ├── db/database.ts      # SQLite user/bet storage
│       ├── handlers/           # Bot command handlers
│       │   ├── start.ts        # Wallet creation
│       │   ├── markets.ts      # Market listing
│       │   ├── betting.ts      # Bet placement
│       │   ├── mybets.ts       # User positions
│       │   ├── wallet.ts       # Wallet management
│       │   └── settings.ts     # Bot settings
│       └── services/           # External integrations
│           ├── privy.ts        # Privy wallet API
│           ├── pyth.ts         # Pyth price feeds
│           └── blockchain.ts   # BSC contract calls
└── scripts/                # Admin scripts
    ├── create-market.ts    # Create new markets
    └── resolve-markets.ts  # Auto-resolve expired markets
```

## ⚙️ Setup

### Prerequisites

- Node.js 18+
- Foundry (`curl -L https://foundry.paradigm.xyz | bash`)
- A Telegram Bot Token (from [@BotFather](https://t.me/BotFather))
- A Privy account ([privy.io](https://privy.io))
- BSC testnet BNB ([faucet](https://www.bnbchain.org/en/testnet-faucet))

### 1. Smart Contracts

```bash
cd contracts
forge install
forge build
forge test  # 51 tests should pass

# Deploy to BSC testnet
cp .env.example .env
# Edit .env with your deployer private key and RPC URL
forge script script/Deploy.s.sol --rpc-url $BSC_TESTNET_RPC_URL --broadcast
```

### 2. Telegram Bot

```bash
cd bot
npm install
cp .env.example .env
```

Edit `.env`:
```
BOT_TOKEN=your_telegram_bot_token
PRIVY_APP_ID=your_privy_app_id
PRIVY_APP_SECRET=your_privy_app_secret
BSC_RPC_URL=https://bsc-testnet-rpc.publicnode.com
MARKET_FACTORY_ADDRESS=0x_deployed_factory_address
CHAIN_ID=97
```

```bash
npm run dev  # Start bot in development mode
```

## 📊 Contract Stats

| Metric | Value |
|--------|-------|
| `bet()` gas | ~98,000 |
| `resolve()` gas | ~96,000 |
| `claim()` gas | ~29,000 |
| `createMarket()` gas | ~440,000 |
| Test count | 51 (37 Market + 14 Factory) |
| Protocol fee | 3% |
| Min bet | 0.001 BNB |
| Anti-frontrun lock | 60s before expiry |

## 🔐 Security

- **ReentrancyGuard** on all payout functions
- **Pausable** emergency controls
- **Checks-Effects-Interactions** pattern throughout
- **24h auto-cancel** for unresolved markets
- **One-sided market refunds** — if everyone bets the same way, everyone gets refunded
- **Exact-price tie refunds** — fair handling of edge cases

## 🗺️ Roadmap

- [x] Core smart contracts (Market + MarketFactory)
- [x] Comprehensive test suite (51 tests)
- [x] Telegram bot with Privy wallets
- [ ] BSC testnet deployment
- [ ] Market creation & resolution automation
- [ ] User notifications on market resolution
- [ ] Leaderboard
- [ ] Multi-chain support

## 👥 Team

<!-- Add team info here -->

---

**Built for the Good Vibes Only: OpenClaw Edition Hackathon** 🏆
