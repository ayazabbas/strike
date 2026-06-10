# Contract Architecture

## Overview

Strike's protocol is composed of three live on-chain market surfaces: the FBA orderbook stack, the standard parimutuel pool stack, and the native-token / Flap Token Pool stack.

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
ParimutuelPoolManager ──→ ParimutuelVault (pool collateral escrow)
       │
       ▼
ParimutuelRedemption

ParimutuelAIResolver ──→ Flap AI Oracle
ParimutuelPythResolver ──→ Pyth Oracle

NativeTokenParimutuelFactory
  │
  └── NativeTokenPoolManager ──→ NativeTokenPoolVault (BEP20 escrow)
          │
          ▼
     NativeTokenPoolRedemption

NativeTokenPoolAIResolver ──→ Flap AI Oracle
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
| **FeeModel** | Fee calculation | Singleton |
| **ParimutuelFactory** | Creates and resolves pool markets | Singleton |
| **ParimutuelPoolManager** | Buys, pool accounting, probability/payout curve | Singleton |
| **ParimutuelVault** | Standard pool collateral custody | Singleton |
| **ParimutuelRedemption** | Pool winner claims and invalid-market refunds | Singleton |
| **ParimutuelAIResolver** | AI resolution for pool markets | Singleton |
| **ParimutuelPythResolver** | Pyth threshold resolution for pool markets | Singleton |
| **NativeTokenParimutuelFactory** | Creates Flap Token Pool markets with hosted metadata + on-chain prompts | Singleton |
| **NativeTokenPoolManager** | Flap Token Pool buys and accounting | Singleton |
| **NativeTokenPoolVault** | BEP20 collateral custody for Flap Token Pools | Singleton |
| **NativeTokenPoolRedemption** | Flap Token Pool claims, refunds, and bond payouts | Singleton |
| **NativeTokenPoolAIResolver** | FLAP AI resolution for native-token pools | Singleton |

## Design Principles

**Separate market engines.** Strike treats FBA orderbook markets, standard parimutuel pools, and native-token Flap Token Pools as separate on-chain primitives. Orderbook markets optimize for active binary trading; pool markets optimize for 2–8 outcome predictions with simple buy-and-claim UX; Flap Token Pools add creator-launched BEP20 collateral and FLAP AI resolution.

**Per-market isolation.** Each market's orderbook state is isolated via per-market mappings within the singleton OrderBook contract. OrderBook uses bid-side and ask-side segment trees per market, preventing cross-market contention and bounding worst-case gas costs to a single market's depth.

**Bounded iteration.** No contract function iterates over an unbounded set. Segment trees provide O(log N) operations. Batch order count is capped at MAX_ORDERS_PER_BATCH (1600) with automatic overflow to the next batch.

**Split pool timing.** Parimutuel V2 markets track `tradingCloseTime` separately from `resolutionTime`, so buying can close before the event or oracle timestamp used for resolution.

**Chunked settlement.** `clearBatch(marketId)` computes the clearing price and settles up to `SETTLE_CHUNK_SIZE` orders per call. Small batches complete in one transaction; larger batches settle through repeated calls. The contract reads `batchOrderIds[marketId][batchId]` internally — no order IDs are passed by the caller. Settlement uses the clearing price, not each order's limit tick.

**Permissionless operations.** Clearing and Pyth resolution are callable by anyone; hosted keepers normally perform them. Current core CLOB contracts do not pay resolver or clearing bounties.

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
