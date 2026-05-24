# 合约架构

## 概览

STRIKE 协议由三类实时链上市场形态组成：FBA 订单簿 stack、标准 parimutuel pool stack，以及 native-token / FLAP Token Pool stack。

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

## 合约关系

| 合约 | Role | Pattern |
|----------|------|---------|
| **MarketFactory** | 部署并注册市场 | Singleton |
| **订单簿** | 下单、取消、存储 | Singleton（每个市场的状态通过 `mapping(uint256 => Market)` 保存） |
| **BatchAuction** | 清算算法与 batch 结果 | 与订单簿集成 |
| **金库** | 抵押资产托管、锁定与 accounting | Singleton |
| **OutcomeToken** | ERC-1155 YES/NO 代币（用于未来市场类型；当前 5-min 市场使用 internal positions） | Singleton |
| **PythResolver** | 使用 Pyth price feed 结算 | Singleton（按市场调用） |
| **AIResolver** | 使用 AI 预言机结算（FLAP） | Singleton（按市场调用） |
| **SegmentTree** | 价格档位聚合 volume | Library（由订单簿使用） |
| **FeeModel** | 费用计算与 bounties | Library 或单例 |
| **ParimutuelFactory** | 创建和结算彩池市场 | Singleton |
| **ParimutuelPoolManager** | 买入、pool accounting、probability/payout curve | Singleton |
| **ParimutuelVault** | 标准 pool 抵押资产托管 | Singleton |
| **ParimutuelRedemption** | Pool 胜出方 claim 与无效市场退款 | Singleton |
| **ParimutuelAIResolver** | 彩池市场的 AI 结算 | Singleton |
| **ParimutuelPythResolver** | 彩池市场的 Pyth threshold 结算 | Singleton |
| **NativeTokenParimutuelFactory** | 使用 hosted metadata 与链上 prompts 创建 FLAP 代币彩池市场 | Singleton |
| **NativeTokenPoolManager** | FLAP Token Pool 买入与 accounting | Singleton |
| **NativeTokenPoolVault** | FLAP 代币池的 BEP20 抵押资产托管 | Singleton |
| **NativeTokenPoolRedemption** | FLAP Token Pool claims、退款与 bond payouts | Singleton |
| **NativeTokenPoolAIResolver** | native-token pools 的 FLAP AI 结算 | Singleton |

## 设计原则

**分离市场引擎。** STRIKE 将 FBA 订单簿市场、标准 parimutuel pools 与 native-token FLAP 代币池视为彼此独立的链上 primitives。订单簿市场针对活跃二元交易优化；彩池市场针对 2–8 结果预测优化，提供简单的 buy-and-claim UX；FLAP 代币池增加了由创建者发起的 BEP20 抵押资产与 FLAP AI 结算。

**按市场隔离。** 每个市场的订单簿状态都通过单例订单簿合约中的 per-market mappings 隔离。Segment tree 按市场、按 side 分配，避免跨市场争用，并将最坏情况下的 Gas 成本限制在单个市场的 depth 内。

**有界迭代。** 任何合约函数都不会遍历无界集合。Segment tree 提供 O(log N) 操作。Batch 订单数量上限为 MAX_ORDERS_PER_BATCH (1600)，超出部分会自动溢出到下一个批次。

**分离 pool 时间。** Parimutuel V2 市场分别跟踪 `tradingCloseTime` 与 `resolutionTime`，因此买入可以在事件发生时关闭，而预言机时间戳则用于结算。

**原子化结算。** `clearBatch(marketId)` 会在单笔交易中清算批次并结算所有订单。合约会在内部读取 `batchOrderIds[marketId][batchId]`，调用方无需传入订单 ID。结算使用清算价格，而不是各订单的限价 tick，多余抵押资产会在同一流程中退回。

**无需许可的操作。** 任何人都可以调用清算和结算。经济激励确保这些操作无需依赖受信任的 operator 也会发生。

## 访问控制 Graph

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

**Role 摘要:**
- 订单簿中的 `OPERATOR_ROLE` 授予 BatchAuction 及 MarketFactory。
- 金库中的 `PROTOCOL_ROLE` 授予订单簿、BatchAuction 及 Redemption。
- OutcomeToken 中的 `MINTER_ROLE` 授予 BatchAuction 及 Redemption。
- MarketFactory 中的 `ADMIN_ROLE` 授予 PythResolver 及 AIResolver。

## Sequence: Approve → 提交订单 → Clear（原子化）→ Redeem

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
