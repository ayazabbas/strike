# Contract Architecture

## Overview

Strike's protocol is composed of eight core contracts:

```
MarketFactory (singleton)
  │
  ├── Creates markets (registers in OrderBook via mapping)
  ├── Manages protocol parameters
  └── Admin controls
       │
       ▼
┌──────────────────────────────────────────────────────┐
│  Singleton Contracts (per-market state via mappings)  │
│                                                       │
│  OrderBook ←→ BatchAuction (atomic clearing+settle)  │
│      │              │                                 │
│      ▼              ▼                                 │
│  SegmentTree    BatchResult storage                   │
│  (per-side)     (per-batch)                          │
└──────────────────────────────────────────────────────┘
       │                    │
       ▼                    ▼
    Vault              OutcomeToken
 (internal escrow)     (ERC-1155)
       │                    │
       ▼                    ▼
  PythResolver ──→ Redemption
       │
  Pyth Oracle (on-chain)
```

## Contract Relationships

| Contract | Role | Pattern |
|----------|------|---------|
| **MarketFactory** | Deploys + registers markets | Singleton |
| **OrderBook** | Order placement, cancellation, storage | Singleton (per-market state via `mapping(uint256 => Market)`) |
| **BatchAuction** | Clearing algorithm, batch results | Integrated with OrderBook |
| **Vault** | Collateral custody, locks, accounting | Singleton |
| **OutcomeToken** | ERC-1155 YES/NO tokens | Singleton |
| **PythResolver** | Oracle verification, resolution | Singleton (called per-market) |
| **SegmentTree** | Price-level aggregate volumes | Library (used by OrderBook) |
| **FeeModel** | Fee calculation, bounties | Library or singleton |

## Design Principles

**Per-market isolation.** Each market's orderbook state is isolated via per-market mappings within the singleton OrderBook contract. Segment trees are allocated per-side per-market, preventing cross-market contention and bounding worst-case gas costs to a single market's depth.

**Bounded iteration.** No contract function iterates over an unbounded set. Segment trees provide O(log N) operations. Claim and prune functions take explicit order ID arrays from the caller.

**Atomic settlement.** `clearBatch(marketId, orderIds[])` clears the batch and settles all provided orders in a single transaction. The keeper passes the order IDs to settle inline — no separate claim step is needed. This simplifies the UX and removes the need for users to submit a second transaction.

**Permissionless operations.** Clearing, resolution, and pruning are all callable by anyone. Economic incentives (resolver bounty) ensure they happen without relying on trusted operators.

## Access Control Graph

```
                   ┌──────────────┐
                   │   Deployer   │
                   │ (admin EOA)  │
                   └──────┬───────┘
                          │ DEFAULT_ADMIN_ROLE
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
    ┌──────────┐   ┌──────────┐   ┌──────────┐
    │ FeeModel │   │  Vault   │   │OrderBook │
    └──────────┘   └────┬─────┘   └────┬─────┘
                        │              │
              PROTOCOL_ │    OPERATOR_ │
              ROLE      │    ROLE      │
          ┌─────┬───────┤    ┌────────┤
          ▼     ▼       ▼    ▼        ▼
     ┌────────┐ │  ┌────────┐  ┌──────────────┐
     │Redemp- │ │  │ Batch  │  │MarketFactory │
     │tion    │ │  │Auction │  └──────┬───────┘
     └────────┘ │  └────┬───┘    ADMIN│_ROLE
                │       │             ▼
     ┌──────────┴──┐    │    ┌──────────────┐
     │ OutcomeToken │◄───┘    │PythResolver  │
     └─────────────┘         └──────────────┘
              ▲  MINTER_ROLE
              │
     BatchAuction, Redemption
```

**Role Summary:**
- `OPERATOR_ROLE` on OrderBook → granted to BatchAuction + MarketFactory
- `PROTOCOL_ROLE` on Vault → granted to OrderBook + BatchAuction + Redemption
- `MINTER_ROLE` on OutcomeToken → granted to BatchAuction + Redemption
- `ADMIN_ROLE` on MarketFactory → granted to PythResolver

## Sequence: Place Order → Clear → Claim → Redeem

```
User           Vault         OrderBook      BatchAuction    OutcomeToken   Redemption
 │               │               │               │               │            │
 │──placeOrder(){ msg.value }──→│               │               │            │
 │               │◄─depositFor()─│               │               │            │
 │               │◄──lock()─────│               │               │            │
 │               │               │               │               │            │
 │  (batch interval elapses)     │               │               │            │
 │               │               │               │               │            │
Keeper─────────────────────clearBatch(mktId, orderIds[])────────→│            │
 │               │               │◄─findClearing─│               │            │
 │               │◄──settleFill─────────────────│  (inline)     │            │
 │               │               │◄─reduceOrder─│               │            │
 │               │               │               │──mintSingle()→│            │
 │◄──BNB refund──│               │               │  (unfilled)  │            │
 │               │               │               │               │            │
 │  (market expires + resolved via PythResolver) │               │            │
 │               │               │               │               │            │
 │──redeem()─────────────────────────────────────────────────────────────────→│
 │               │               │               │               │◄─redeem()─│
 │               │◄──redeemFromPool──────────────────────────────────────────│
 │◄──BNB payout──│               │               │               │            │
```
