# Contract Architecture

## Overview

Strike uses two contracts working together:

```
MarketFactory (singleton)
    │
    ├── createMarket() → deploys Market clone
    ├── getMarkets() → lists all markets
    └── manages admin/keeper permissions
         │
         ▼
    Market (EIP-1167 clone)
    Market (EIP-1167 clone)
    Market (EIP-1167 clone)
    ...each is an independent prediction market
```

## EIP-1167 Minimal Proxy Pattern

Each market is deployed as a **minimal proxy clone** of a single implementation contract. This is dramatically cheaper than deploying full contracts:

| Approach | Gas Cost |
|----------|----------|
| Full contract deploy | ~2,000,000 |
| EIP-1167 clone | ~440,000 |

The factory deploys a lightweight proxy (~45 bytes) that delegates all calls to the implementation. Each clone has its own storage but shares the implementation's code.

## Contract Interactions

```
User                    MarketFactory              Market Clone
  │                          │                          │
  │   (admin/keeper only)    │                          │
  │ ─── createMarket() ────▶│                          │
  │                          │── deploy clone ────────▶ │
  │                          │── initialize() ────────▶ │
  │                          │   (set pyth, priceId,    │
  │                          │    duration, strike)     │
  │                          │                          │
  │ ─── bet(UP, {value}) ──────────────────────────────▶│
  │                          │                          │── record bet
  │                          │                          │── calc shares
  │                          │                          │
  │   (after expiry)         │                          │
  │ ─── resolve(pythData) ─────────────────────────────▶│
  │                          │                          │── verify pyth
  │                          │                          │── determine winner
  │                          │                          │── calc payouts
  │                          │                          │
  │ ─── claim() ───────────────────────────────────────▶│
  │ ◀── BNB payout ────────────────────────────────────│
```

## State Machine

Each market follows a linear state progression:

```
Open → Closed → Resolved
                    └──→ Cancelled (if resolution fails)
```

| State | Description | Transitions |
|-------|-------------|-------------|
| **Open** | Accepting bets. Starts at creation. | → Closed (when `tradingEnd` reached) |
| **Closed** | Betting stopped, awaiting resolution. | → Resolved or → Cancelled |
| **Resolved** | Winner determined, payouts available. | Terminal state. |
| **Cancelled** | Refunds available. | Terminal state. |

**Note:** The `state` variable stores the base state, but `getCurrentState()` computes the effective state based on timestamps. For example, an Open market past its `tradingEnd` is effectively Closed even if `state` hasn't been updated on-chain.

## Key Design Decisions

### Parimutuel over Orderbook
An orderbook requires matching engines and complex liquidity management. The parimutuel model is simpler: all bets pool together, winners split proportionally. Perfect for an MVP.

### Trading Deadline at Halfway
Betting stops at the halfway point of the market duration (2.5 minutes for a 5-minute market). This prevents last-second bets that could exploit price movements already visible in the mempool.

### Fee on Winnings Only
The 3% protocol fee is charged on the winning pool, not the total pool. This means losers lose exactly what they bet — no additional fee on top.

### Permissionless Resolution
Anyone can call `resolve()` after expiry, not just the admin. This makes the system more trustless — if the keeper goes down, any user can resolve markets.
