# Strike — Project Brief

## What We're Building

**Strike** is a fully onchain prediction market on BNB Chain where users bet on whether an asset's price will go UP or DOWN by a specific time.

## Core Concept

- Users place predictions: "Will BTC be above $X at Y time?"
- Markets are resolved trustlessly using **Pyth price feeds**
- Frontend is a **Telegram mini-app**
- All logic lives onchain (BSC or opBNB)

## MVP Scope (Hackathon - 9 days)

We're building for the **Good Vibes Only: OpenClaw Edition** hackathon (deadline Feb 19, 2026).

### Must Have (MVP)

1. **Smart Contracts (Solidity)**
   - Binary UP/DOWN prediction markets
   - Fixed-odds pool model (not orderbook — simpler for MVP)
   - Pyth integration for strike price at market creation
   - Pyth integration for resolution at expiry
   - Winner payout distribution

2. **Telegram Mini-App**
   - View active markets (BTC, BNB)
   - Connect wallet (WalletConnect or TON Connect)
   - Place prediction (pick UP/DOWN, stake BNB)
   - View your positions
   - See resolved markets + results

3. **Supported Assets**
   - BTC and BNB only for MVP

4. **Time Windows**
   - Fixed durations: 1hr, 4hr, 24hr

### NOT in MVP (Future Features)

- Batch auction orderbook model
- AI market making framework
- Natural language strategy input
- Custom market creation
- Additional assets beyond BTC/BNB

## Tech Stack

- **Contracts**: Solidity, Foundry or Hardhat
- **Chain**: BNB Smart Chain (BSC) or opBNB
- **Oracle**: Pyth Network
- **Frontend**: React/Next.js, Telegram Mini Apps SDK
- **Wallet**: WalletConnect

## Success Criteria

1. User can place a prediction via Telegram
2. Contract deployed on BSC/opBNB with verifiable transactions
3. Pyth price resolution works
4. Demo-able end-to-end flow
5. Judges understand value prop in < 1 minute

## Team

Built by Ayaz Abbas (@ayazabbas) — Platform Engineer at Douro Labs (Pyth)

## Constraints

- 9 days to build
- Must prove execution onchain (hackathon requirement)
- No token launch during hackathon
- AI tooling encouraged (this is an "AI-first" hackathon)
