# Contract Architecture

## Overview

Strike's protocol is composed of two first-class on-chain market engines: the FBA orderbook stack and the parimutuel pool stack.

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

  AIResolver ───→ Redemption (via MarketFactory.setResolved)
       │
  Flap AI Oracle (on-chain)

ParimutuelFactory
  │
  ├── Creates 2–8 outcome pool markets
  ├── Tracks tradingCloseTime and resolutionTime separately
  └── Coordinates admin / AI / Pyth resolution
       │
       ▼
ParimutuelPoolManager ──→ ParimutuelVault (USDT escrow)
       │
       ▼
ParimutuelRedemption

ParimutuelAIResolver ──→ Flap AI Oracle
ParimutuelPythResolver ──→ Pyth Oracle
```

## Contract Relationships

| Contract | Role | Pattern |
|----------|------|---------|
| **MarketFactory** | Deploys + registers markets | Singleton |
| **OrderBook** | Order placement, cancellation, storage | Singleton (per-market state via `mapping(uint256 => Market)`) |
| **BatchAuction** | Clearing algorithm, batch results | Integrated with OrderBook |
| **Vault** | Collateral custody, locks, accounting | Singleton |
| **OutcomeToken** | ERC-1155 YES/NO tokens (used for future market types; current 5-min markets use internal positions) | Singleton |
| **PythResolver** | Pyth price feed resolution | Singleton (called per-market) |
| **AIResolver** | AI oracle resolution (Flap) | Singleton (called per-market) |
| **SegmentTree** | Price-level aggregate volumes | Library (used by OrderBook) |
| **FeeModel** | Fee calculation, bounties | Library or singleton |
| **ParimutuelFactory** | Creates and resolves pool markets | Singleton |
| **ParimutuelPoolManager** | Buys, pool accounting, probability/payout curve | Singleton |
| **ParimutuelVault** | Pool-market USDT collateral custody | Singleton |
| **ParimutuelRedemption** | Pool winner claims and invalid-market refunds | Singleton |
| **ParimutuelAIResolver** | AI resolution for pool markets | Singleton |
| **ParimutuelPythResolver** | Pyth threshold resolution for pool markets | Singleton |

## Design Principles

**Two market engines.** Strike treats FBA orderbook markets and parimutuel pool markets as separate on-chain primitives. Orderbook markets optimize for active binary trading; parimutuel markets optimize for 2–8 outcome pool predictions with simple buy-and-claim UX.

**Per-market isolation.** Each market's orderbook state is isolated via per-market mappings within the singleton OrderBook contract. Segment trees are allocated per-side per-market, preventing cross-market contention and bounding worst-case gas costs to a single market's depth.

**Bounded iteration.** No contract function iterates over an unbounded set. Segment trees provide O(log N) operations. Batch order count is capped at MAX_ORDERS_PER_BATCH (1600) with automatic overflow to the next batch.

**Split pool timing.** Parimutuel V2 markets track `tradingCloseTime` separately from `resolutionTime`, so buying can close before the event or oracle timestamp used for resolution.

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
- `ADMIN_ROLE` on MarketFactory → granted to PythResolver + AIResolver

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
