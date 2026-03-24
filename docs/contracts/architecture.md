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
 (internal escrow)     (ERC-1155; future market types)
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
| **OutcomeToken** | ERC-1155 YES/NO tokens (used for future market types; current 5-min markets use internal positions) | Singleton |
| **PythResolver** | Oracle verification, resolution | Singleton (called per-market) |
| **SegmentTree** | Price-level aggregate volumes | Library (used by OrderBook) |
| **FeeModel** | Fee calculation, bounties | Library or singleton |

## Design Principles

**Per-market isolation.** Each market's orderbook state is isolated via per-market mappings within the singleton OrderBook contract. Segment trees are allocated per-side per-market, preventing cross-market contention and bounding worst-case gas costs to a single market's depth.

**Bounded iteration.** No contract function iterates over an unbounded set. Segment trees provide O(log N) operations. Batch order count is capped at MAX_ORDERS_PER_BATCH (1600) with automatic overflow to the next batch.

**Atomic settlement.** `clearBatch(marketId)` clears the batch and settles all orders in a single transaction. The contract reads `batchOrderIds[marketId][batchId]` internally — no order IDs are passed by the caller. Settlement uses the clearing price (not each order's limit tick), and excess collateral is refunded inline.

**Permissionless operations.** Clearing and resolution are callable by anyone. Economic incentives ensure they happen without relying on trusted operators.

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

## Sequence: Approve → Place Order → Clear (atomic) → Redeem

```
User           Vault(USDT)    OrderBook      BatchAuction    OutcomeToken   Redemption
 │               │               │               │               │            │
 │──approve(Vault, amount)──→   │               │               │            │
 │──placeOrder(mktId,side,tick,lots)───────────→│               │            │
 │               │◄─depositFor()─│  (transferFrom)              │            │
 │               │◄──lock()─────│               │               │            │
 │               │               │               │               │            │
 │  (keeper decides to clear)    │               │               │            │
 │               │               │               │               │            │
Keeper──────────────────────clearBatch(marketId)───────────────→│            │
 │               │               │◄─findClearing─│               │            │
 │               │               │◄─getBatchOrderIds─│           │            │
 │               │◄──settleFill──────────────────│  (per order) │            │
 │               │               │◄─reduceOrder──│               │            │
 │               │               │               │──mintSingle()→│            │
 │               │               │               │  (or internal │            │
 │               │               │               │   position    │            │
 │               │               │               │   credit for  │            │
 │               │               │               │   useInternal │            │
 │               │               │               │   Positions   │            │
 │               │               │               │   markets)    │            │
 │◄──USDT refund─│               │               │  (excess)    │            │
 │               │               │               │               │            │
 │  (market expires + resolved via PythResolver) │               │            │
 │               │               │               │               │            │
 │──redeem()─────────────────────────────────────────────────────────────────→│
 │               │               │               │               │◄─redeem()─│
 │               │◄──redeemFromPool──────────────────────────────────────────│
 │◄──USDT payout─│               │               │               │            │
```
