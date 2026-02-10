# Requirements: Strike

**Defined:** 2026-02-10
**Core Value:** Users can place a binary UP/DOWN prediction on an asset's price and get paid out fairly when the market resolves — all onchain, all trustless.

## v1 Requirements

Requirements for v1.0 MVP (Hackathon deadline: Feb 19, 2026). Each maps to roadmap phases.

### Market Mechanics

- [ ] **MKT-01**: User can see binary UP/DOWN prediction markets with parimutuel payout model on BSC
- [ ] **MKT-02**: Markets are auto-created on a schedule for BTC and BNB (1hr, 4hr, 24hr windows)
- [ ] **MKT-03**: Strike price is captured from Pyth oracle at market creation
- [ ] **MKT-04**: Protocol fee (3%) is deducted from winning pool on resolution
- [ ] **MKT-05**: Minimum bet size of 0.001 BNB is enforced
- [ ] **MKT-06**: Betting locks 60 seconds before market expiry

### Betting

- [ ] **BET-01**: User can place UP or DOWN prediction by staking BNB
- [ ] **BET-02**: User can see real-time payout preview before placing bet
- [ ] **BET-03**: User can see protocol fee disclosure before confirming bet
- [ ] **BET-04**: User receives transaction status feedback (pending/confirmed/failed)

### Resolution

- [ ] **RES-01**: Anyone can trigger market resolution after expiry (permissionless)
- [ ] **RES-02**: Resolution uses Pyth price feed with staleness validation (max 60s)
- [ ] **RES-03**: One-sided markets (all bets on one side) refund all participants
- [ ] **RES-04**: Exact price tie at resolution triggers refund for all

### Positions & Payouts

- [ ] **POS-01**: User can view active positions with stake and estimated payout
- [ ] **POS-02**: User can view resolved markets and results
- [ ] **POS-03**: User can claim winnings from resolved markets
- [ ] **POS-04**: User can receive refund for cancelled markets

### Telegram Mini-App

- [ ] **APP-01**: App loads as Telegram Mini App on Android and iOS
- [ ] **APP-02**: User can connect BSC wallet via WalletConnect
- [ ] **APP-03**: User can view active markets with time remaining, pool sizes, and strike price
- [ ] **APP-04**: User can see real-time BTC/BNB prices from Pyth
- [ ] **APP-05**: User can see countdown timers to market expiry (color-coded)
- [ ] **APP-06**: User can see UP vs DOWN pool distribution with payout multipliers
- [ ] **APP-07**: Market data auto-refreshes without manual reload

### Automation

- [ ] **AUTO-01**: Keeper script auto-resolves expired markets with Pyth price data
- [ ] **AUTO-02**: Scheduler script auto-creates markets on a fixed schedule

## v2 Requirements

Deferred to post-hackathon. Tracked but not in current roadmap.

### Notifications

- **NOTF-01**: User receives Telegram push notification when position resolves
- **NOTF-02**: User receives notification when market is closing soon (15min warning)
- **NOTF-03**: User can configure notification preferences

### Gamification

- **GAME-01**: User can see leaderboard ranked by profit, win rate, and volume
- **GAME-02**: User earns badges for achievements (streak, volume milestones)

### Growth

- **GROW-01**: User can share prediction link with friends via Telegram
- **GROW-02**: Referral system with bonus for first bet
- **GROW-03**: Additional assets beyond BTC/BNB (ETH, SOL)
- **GROW-04**: Custom time windows (15min, 6hr, 48hr)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Order book / AMM trading | Defeats parimutuel simplicity, massive complexity |
| User-created markets | Fragments liquidity, moderation burden, oracle complexity |
| Leverage / margin trading | Liquidation mechanics, regulatory concerns |
| Early exit / position selling | Kills parimutuel model, requires AMM or orderbook |
| Fiat on-ramp | Regulatory nightmare (KYC/AML), out of scope for MVP |
| Native token ($STRIKE) | Hackathon rules prohibit, distracts from core product |
| Social features (chat) | Scope creep, moderation burden |
| Advanced analytics / charting | Over-engineering for binary predictions |
| Cross-chain deployment | Master BSC first |
| opBNB deployment | BSC chosen for better tooling and Pyth support |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| MKT-01 | — | Pending |
| MKT-02 | — | Pending |
| MKT-03 | — | Pending |
| MKT-04 | — | Pending |
| MKT-05 | — | Pending |
| MKT-06 | — | Pending |
| BET-01 | — | Pending |
| BET-02 | — | Pending |
| BET-03 | — | Pending |
| BET-04 | — | Pending |
| RES-01 | — | Pending |
| RES-02 | — | Pending |
| RES-03 | — | Pending |
| RES-04 | — | Pending |
| POS-01 | — | Pending |
| POS-02 | — | Pending |
| POS-03 | — | Pending |
| POS-04 | — | Pending |
| APP-01 | — | Pending |
| APP-02 | — | Pending |
| APP-03 | — | Pending |
| APP-04 | — | Pending |
| APP-05 | — | Pending |
| APP-06 | — | Pending |
| APP-07 | — | Pending |
| AUTO-01 | — | Pending |
| AUTO-02 | — | Pending |

**Coverage:**
- v1 requirements: 22 total
- Mapped to phases: 0
- Unmapped: 22 (pending roadmap creation)

---
*Requirements defined: 2026-02-10*
*Last updated: 2026-02-10 after initial definition*
