# Strike

## What This Is

Strike is a fully onchain prediction market on BNB Smart Chain (BSC) where users bet on whether an asset's price will go UP or DOWN by a specific time. Users interact through a Telegram mini-app, placing parimutuel bets on BTC and BNB price movements across fixed time windows. Markets are created automatically and resolved trustlessly using Pyth price feeds.

## Core Value

Users can place a binary UP/DOWN prediction on an asset's price and get paid out fairly when the market resolves — all onchain, all trustless.

## Current Milestone: v1.0 MVP

**Goal:** Ship a working onchain prediction market with Telegram mini-app frontend for the hackathon deadline (Feb 19, 2026).

**Target features:**
- Smart contracts: parimutuel binary markets, auto-creation, Pyth oracle, permissionless resolution
- Telegram mini-app: view markets, connect wallet, place predictions, track positions
- Protocol fee and payout distribution

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Binary UP/DOWN prediction markets with parimutuel payout model
- [ ] Auto-created markets on a schedule for BTC and BNB
- [ ] Pyth integration for strike price (current price at market creation)
- [ ] Pyth integration for trustless resolution at expiry (anyone can trigger)
- [ ] Winner payout distribution proportional to pool share
- [ ] Protocol fee on winnings (2-5%)
- [ ] Fixed time windows: 1hr, 4hr, 24hr
- [ ] Minimum bet size (~0.001 BNB), no maximum
- [ ] Telegram mini-app to view active markets
- [ ] Wallet connection (WalletConnect)
- [ ] Place prediction (pick UP/DOWN, stake BNB)
- [ ] View your positions and history
- [ ] See resolved markets and results

### Out of Scope

- Batch auction orderbook model — future complexity, not MVP
- AI market making framework — post-hackathon feature
- Natural language strategy input — post-hackathon feature
- Custom market creation by users — admin/auto-created only for MVP
- Additional assets beyond BTC/BNB — keep scope tight
- Token launch — hackathon rules prohibit this
- opBNB deployment — BSC chosen for better tooling and Pyth support

## Context

- Building for the **Good Vibes Only: OpenClaw Edition** hackathon (deadline Feb 19, 2026)
- Builder: Ayaz Abbas (@ayazabbas) — Platform Engineer at Douro Labs (Pyth Network)
- Deep familiarity with Pyth oracle integration (works on it professionally)
- AI tooling encouraged — this is an "AI-first" hackathon
- Must prove execution onchain (hackathon requirement)
- Parimutuel model: all bets pooled per side (UP/DOWN), winners split the total pool proportionally minus protocol fee
- Strike price = current Pyth price when market is created
- Markets auto-created on a schedule (e.g., new 1hr BTC market every hour)
- Resolution is permissionless — anyone can call resolve after expiry, pulling Pyth price

## Constraints

- **Timeline**: 9 days to build (hackathon deadline Feb 19, 2026)
- **Chain**: BNB Smart Chain (BSC)
- **Oracle**: Pyth Network price feeds
- **Frontend**: Telegram Mini Apps SDK (must work inside Telegram)
- **Wallet**: WalletConnect for wallet connection
- **Assets**: BTC and BNB only
- **Contracts**: Solidity (Foundry or Hardhat)
- **Frontend Stack**: React/Next.js

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Parimutuel payout model | Simplest fair model — no need for orderbook or market maker | — Pending |
| Auto-created markets | Reduces complexity vs user-created; consistent market availability | — Pending |
| Permissionless resolution | More trustless, aligns with onchain ethos; anyone can trigger after expiry | — Pending |
| BSC over opBNB | Better tooling, established Pyth support, more users | — Pending |
| Current Pyth price as strike | Most intuitive — "will price be above current price in X time?" | — Pending |
| Small protocol fee (2-5%) | Standard for prediction markets, sustainable model | — Pending |

---
*Last updated: 2026-02-10 after initialization*
