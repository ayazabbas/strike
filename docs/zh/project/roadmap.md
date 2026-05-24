# 路线图

## 已完成：PoC (v0)

为 *Good Vibes Only: OpenClaw Edition* hackathon 构建的 proof-of-concept。

- Parimutuel pool model（无订单簿）
- `Market.sol` + `MarketFactory.sol`，包含 51 个 tests
- 使用 Privy embedded wallets 的 Telegram bot
- Pyth 预言机结算
- Keeper service（自动创建 + 自动结算）

保留在 `poc` branch。

## 已完成：CLOB (v1)

### Phase 1A - Core Primitives

- [x] OutcomeToken (ERC-1155)
- [x] Segment tree library
- [x] 抵押资产 Vault
- [x] 费用模型（统一 20 bps）
- [x] Unit tests (40+)

### Phase 1B - 订单簿与批量拍卖

- [x] 订单类型（GoodTilCancel、GoodTilBatch）
- [x] OrderBook 合约
- [x] BatchAuction 清算 engine
- [x] 原子化内联结算（clearBatch 在一笔交易中结算所有订单）
- [x] Integration tests (50+)

### Phase 1C - 市场生命周期与结算

- [x] 带完整状态机的 MarketFactory
- [x] 带 finality gate 与 challenge window 的 PythResolver
- [x] 结果代币赎回
- [x] Full protocol tests (40+)

### Phase 1D - Sell 订单与 Batch Operations

- [x] SellYes / SellNo 订单方向（四边订单簿）
- [x] Token custody：OrderBook 作为 ERC1155Holder
- [x] OutcomeToken 中使用 ESCROW_ROLE 的 `burnEscrow()`
- [x] `placeOrders()`：通过单次 Vault deposit 批量下单
- [x] `replaceOrders()`：通过净额结算实现原子化取消+下单
- [x] 用于 batch operations 的 `OrderParam` struct

*所有合约模块共 292 个 tests passing。*

### Phase 2 - Keeper 与 Indexer 基础设施

- [x] Batch 清算 keeper
- [x] 市场结算 keeper
- [x] Event indexer + REST API + WebSocket
- [x] Telegram bot integration

### Phase 3 - Web 前端

- [x] Next.js 16 交易 terminal
- [x] 实时订单簿 visualization
- [x] 订单管理 + portfolio
- [x] Mobile optimization + PWA

### Phase 4 - Integration, Hardening 与部署

- [ ] End-to-end integration tests
- [ ] Gas optimization pass
- [ ] Security hardening（Slither、Mythril）
- [ ] Private submission support (BEP-322)
- [x] BSC 部署 + soak test
- [x] Documentation

## 已上线 / 近期发布

- **[AI 市场](../protocol/ai-markets.md)** - FLAP AI 预言机结算已实时用于支持的市场类型。
- **[Parimutuel 彩池市场](../protocol/parimutuel-markets.md)** - USDT/STRIKE 多结果彩池市场已上线。
- **[FLAP 代币池](../protocol/flap-token-pools.md)** - 面向 BEP20 抵押资产、由 AI 结算的 token pools 公开创建者流程已上线。

## 未来

- 用于 official FLAP Token Pool creation prompts 的 AI quality gate。
- 在流动性支持的情况下，扩展 multi-asset 与 Pyth 价格源覆盖。
- 可变市场时长（1min、5min、15min、1hr）。

### 近期完成

- [x] BSC 主网重新部署与生产环境 cutover（区块 95210316，previous live deployment 已于 reset 前归档）
- [x] 使用 `amendOrders` 的 canonical BSC 测试网 stack 已上线（区块 103312703）
- [x] 排行榜（PNL + Volume tabs、24H/7D/30D/All、用户名 system）
- [x] Native / FLAP 代币池主网 stack 部署，公开前端已启用。
