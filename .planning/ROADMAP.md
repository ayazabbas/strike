# Roadmap: Strike

## Overview

Strike delivers a fully onchain prediction market in 5 phases over 9 days. Phase 1 establishes smart contract foundation with Pyth oracle integration and parimutuel mechanics. Phase 2 proves Telegram Mini App wallet connection (highest risk). Phase 3 implements core betting flow. Phase 4 adds resolution and payout claiming. Phase 5 automates market creation and polishes UX. Each phase delivers verifiable user-facing value, building toward a working hackathon demo by Feb 19, 2026.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Core Contracts** - Smart contracts with parimutuel mechanics and Pyth oracle
- [ ] **Phase 2: Frontend Foundation** - Telegram Mini App with wallet connection
- [ ] **Phase 3: Betting Flow** - Place bets, view positions, real-time updates
- [ ] **Phase 4: Resolution & Claiming** - Resolve markets and claim payouts
- [ ] **Phase 5: Automation & Polish** - Auto-create markets and final UX polish

## Phase Details

### Phase 1: Core Contracts
**Goal**: Smart contracts deployed to BSC testnet with parimutuel betting mechanics, Pyth oracle integration for strike price and resolution, and emergency controls.

**Depends on**: Nothing (first phase)

**Requirements**: MKT-01, MKT-02, MKT-03, MKT-04, MKT-05, MKT-06, RES-01, RES-02, RES-03, RES-04

**Success Criteria** (what must be TRUE):
  1. Contract accepts bets on UP or DOWN side with minimum 0.001 BNB enforcement
  2. Strike price is captured from Pyth oracle at market creation time
  3. Betting locks 60 seconds before market expiry
  4. Anyone can trigger resolution after expiry using Pyth price feed
  5. One-sided markets and exact price ties trigger refunds to all participants
  6. Protocol fee (3%) is deducted from winning pool on resolution

**Plans**: TBD

Plans:
- [ ] TBD (plans created during plan-phase)

### Phase 2: Frontend Foundation
**Goal**: Telegram Mini App loads on Android and iOS with working BSC wallet connection via WalletConnect, de-risking the highest uncertainty integration.

**Depends on**: Phase 1

**Requirements**: APP-01, APP-02

**Success Criteria** (what must be TRUE):
  1. App loads as Telegram Mini App on Android and iOS devices
  2. User can connect BSC wallet via WalletConnect from Telegram webview
  3. Connected wallet address displays in app
  4. Wallet connection persists across app reloads

**Plans**: TBD

Plans:
- [ ] TBD (plans created during plan-phase)

### Phase 3: Betting Flow
**Goal**: Users can view active markets, place UP/DOWN predictions with real-time pool updates, and track their positions.

**Depends on**: Phase 2

**Requirements**: BET-01, BET-02, BET-03, BET-04, APP-03, APP-04, APP-05, APP-06, APP-07

**Success Criteria** (what must be TRUE):
  1. User can see list of active markets with time remaining, pool sizes, and strike price
  2. User can see real-time BTC/BNB prices from Pyth
  3. User can place UP or DOWN prediction by staking BNB
  4. User sees payout preview and protocol fee disclosure before confirming bet
  5. User receives transaction status feedback (pending/confirmed/failed)
  6. Market data auto-refreshes without manual reload
  7. Countdown timers to market expiry display with color coding
  8. UP vs DOWN pool distribution displays with payout multipliers

**Plans**: TBD

Plans:
- [ ] TBD (plans created during plan-phase)

### Phase 4: Resolution & Claiming
**Goal**: Markets resolve automatically with Pyth price data, and winners can claim payouts proportional to their pool share.

**Depends on**: Phase 1, Phase 3

**Requirements**: POS-01, POS-02, POS-03, POS-04

**Success Criteria** (what must be TRUE):
  1. User can view active positions with stake amount and estimated payout
  2. User can view resolved markets showing final results
  3. User can claim winnings from resolved markets they won
  4. User can receive refunds for cancelled or one-sided markets
  5. Claimed payouts correctly reflect protocol fee deduction and pool share

**Plans**: TBD

Plans:
- [ ] TBD (plans created during plan-phase)

### Phase 5: Automation & Polish
**Goal**: Markets auto-create on schedule, keeper scripts auto-resolve expired markets, and UX is polished for hackathon demo. This phase is buffer and can be cut if timeline slips.

**Depends on**: Phase 4

**Requirements**: AUTO-01, AUTO-02

**Success Criteria** (what must be TRUE):
  1. New markets auto-create on fixed schedule for BTC and BNB (1hr, 4hr, 24hr windows)
  2. Keeper script auto-resolves expired markets without manual intervention
  3. Protocol fee collection is tracked and accessible by contract owner
  4. App provides smooth onboarding flow for first-time users

**Plans**: TBD

Plans:
- [ ] TBD (plans created during plan-phase)

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Core Contracts | 0/TBD | Not started | - |
| 2. Frontend Foundation | 0/TBD | Not started | - |
| 3. Betting Flow | 0/TBD | Not started | - |
| 4. Resolution & Claiming | 0/TBD | Not started | - |
| 5. Automation & Polish | 0/TBD | Not started | - |
