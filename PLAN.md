# Strike 🐍

**Fully Onchain Prediction Market with AI Market Making**

> Simple up/down price predictions, powered by Pyth oracles, with an AI market maker you control through natural language.

---

## 🎯 Vision

Strike is a prediction market where users bet on whether an asset's price will be higher or lower at a future time. Markets are fully onchain, resolved trustlessly via Pyth price feeds, and accessible through a Telegram mini-app.

The twist: an AI-powered market making framework lets users run automated strategies described in plain English, using real-time Pyth feeds.

---

## 🏆 Hackathon Context

| | |
|---|---|
| **Hackathon** | Good Vibes Only: OpenClaw Edition |
| **Prize Pool** | $100,000 (10 winners) |
| **Deadline** | Feb 19, 2026 3PM UTC |
| **Tracks** | Agent + DeFi |
| **Requirements** | Onchain proof (BSC/opBNB), public repo, working demo |

---

## 📦 MVP Scope (Hackathon Submission)

The MVP must be **demo-able** and **show the vision**. Ship the core loop, prove it works.

### Core Features (Must Have)

#### 1. Smart Contracts (Solidity)
- **PredictionMarket.sol** — Core market logic
  - Create market: asset, direction (UP/DOWN), strike price, expiry time
  - Place prediction: user stakes tokens on UP or DOWN
  - Resolve market: pull Pyth price at expiry, distribute winnings
  - Simple fixed-odds model (not orderbook for MVP)
- **PythIntegration** — Interface with Pyth on BNB Chain
  - Fetch price at market creation (for strike price)
  - Fetch price at expiry (for resolution)

#### 2. Telegram Mini-App
- View active markets (BTC, BNB)
- Place a prediction (connect wallet, pick UP/DOWN, stake amount)
- View your positions
- See resolved markets + results

#### 3. Basic Demo Flow
1. Market exists: "Will BTC be above $X at Y time?"
2. User opens Telegram app, connects wallet
3. User picks UP or DOWN, stakes BNB
4. Time passes, market expires
5. Pyth price fetched, market resolved
6. Winner gets payout

### Simplified for MVP

| Full Vision | MVP Simplification |
|-------------|-------------------|
| Batch auction orderbook | Fixed-odds pool (simpler math) |
| Multiple assets | BTC + BNB only |
| AI market maker | Deferred to v1.1 |
| NL strategy input | Deferred to v1.1 |
| Complex time windows | Fixed durations (1hr, 4hr, 24hr) |

---

## 🚀 Post-MVP Features (If Time Permits)

### v1.1 — AI Market Maker
- Telegram bot for market makers
- Describe strategy in natural language: "Provide liquidity when volatility is low, pull when it spikes"
- Bot interprets via LLM, executes using Pyth real-time feeds
- Autonomous onchain execution

### v1.2 — Orderbook Model
- Replace fixed-odds with batch auction orderbook
- Better price discovery
- More capital efficient

### v1.3 — Extended Assets
- Add SOL, ETH, other Pyth-supported assets
- Custom markets (user-created)

---

## 🏗️ Technical Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Telegram Mini-App                     │
│  (React/Next.js + TON Connect or WalletConnect)         │
└─────────────────────┬───────────────────────────────────┘
                      │ API calls
                      ▼
┌─────────────────────────────────────────────────────────┐
│                   Backend Service                        │
│  - Market indexing                                       │
│  - User position tracking                                │
│  - Pyth price caching                                    │
│  (Node.js / Python)                                      │
└─────────────────────┬───────────────────────────────────┘
                      │ RPC calls
                      ▼
┌─────────────────────────────────────────────────────────┐
│              BNB Chain (BSC or opBNB)                   │
│  ┌─────────────────┐  ┌─────────────────┐              │
│  │ PredictionMarket│  │   Pyth Oracle   │              │
│  │    Contract     │◄─┤   (existing)    │              │
│  └─────────────────┘  └─────────────────┘              │
└─────────────────────────────────────────────────────────┘
```

---

## 📁 Project Structure

```
strike/
├── PLAN.md                 # This file
├── README.md               # Project overview + setup
├── contracts/              # Solidity smart contracts
│   ├── PredictionMarket.sol
│   ├── interfaces/
│   └── test/
├── app/                    # Telegram mini-app (frontend)
│   ├── src/
│   └── package.json
├── backend/                # Indexer + API (if needed)
│   └── ...
└── scripts/                # Deployment + testing scripts
```

---

## 🛠️ Tech Stack

| Component | Technology |
|-----------|------------|
| Smart Contracts | Solidity, Hardhat/Foundry |
| Chain | BNB Smart Chain (BSC) or opBNB |
| Oracle | Pyth Network |
| Frontend | React/Next.js, Telegram Mini Apps SDK |
| Wallet | WalletConnect or TON Connect |
| Backend | Node.js or Python (minimal) |
| AI (v1.1) | OpenAI API for NL parsing |

---

## 📅 Timeline

### Day 1-2: Smart Contracts
- [ ] Set up Foundry/Hardhat project
- [ ] Implement PredictionMarket.sol
- [ ] Integrate Pyth price feeds
- [ ] Write basic tests
- [ ] Deploy to BSC testnet

### Day 3-4: Telegram Mini-App
- [ ] Scaffold Telegram mini-app
- [ ] Wallet connection flow
- [ ] Market list view
- [ ] Place prediction UI
- [ ] Position tracking

### Day 5: Integration
- [ ] Connect frontend to contracts
- [ ] End-to-end flow testing
- [ ] Deploy to BSC mainnet (or testnet for demo)

### Day 6: Polish + Demo Prep
- [ ] UI polish
- [ ] Demo script
- [ ] Video recording
- [ ] Documentation

### Day 7-9: Buffer / AI MM (Stretch)
- [ ] If ahead: implement AI market maker
- [ ] If behind: bug fixes + polish

---

## 📋 Submission Checklist

- [ ] Deployed contract address (BSC or opBNB)
- [ ] Transaction hash showing market creation/resolution
- [ ] Public GitHub repo
- [ ] Working demo link (Telegram bot/app)
- [ ] Demo video (< 5 min)
- [ ] README with setup instructions

---

## 🔗 Resources

### Pyth on BNB Chain
- Docs: https://docs.pyth.network/
- BSC Contract: https://docs.pyth.network/price-feeds/contract-addresses/evm
- Price Feed IDs: https://pyth.network/developers/price-feed-ids

### Telegram Mini Apps
- Docs: https://core.telegram.org/bots/webapps
- SDK: https://github.com/AstarNetwork/ton-connect-sdk (for wallet)

### BNB Chain
- BSC Docs: https://docs.bnbchain.org/
- Faucet: https://testnet.bnbchain.org/faucet-smart
- Explorer: https://bscscan.com/

---

## 💡 Demo Script (Draft)

1. **Intro** (30s): "Strike is a prediction market where you bet on price direction, resolved by Pyth oracles."

2. **Show Telegram App** (1m): Open app, show active markets, explain the UI.

3. **Place a Prediction** (1m): Connect wallet, pick "BTC UP in 1 hour", stake 0.01 BNB.

4. **Show Contract** (30s): Point to BSCScan, show the transaction.

5. **Resolution** (1m): Show a resolved market, Pyth price fetch, payout distribution.

6. **Vision** (1m): "Next: AI market makers that run strategies you describe in plain English."

---

## ✅ Success Criteria

1. **Working demo**: User can place a prediction via Telegram
2. **Onchain proof**: Contract deployed, transactions visible
3. **Pyth integration**: Price resolution works
4. **Reproducible**: Anyone can clone repo and run locally
5. **Clear value prop**: Judges understand it in < 1 minute
