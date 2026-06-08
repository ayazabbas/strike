# 安全

## 智能合约安全

### 重入保护

所有会改变状态的外部函数都使用 OpenZeppelin 的 `ReentrancyGuard`。整个代码库遵循 Checks-Effects-Interactions 模式。

### 访问控制

| Function | Access |
|----------|--------|
| `placeOrder()` / `cancelOrder()` | 任何人（需要足够余额） |
| `clearBatch()` | 任何人（permissionless） |
| `resolveMarket()` | 任何人（需要有效 Pyth data） |
| `finalizeResolution()` | 任何人（finality window 之后） |
| `redeem()` | Token holders |
| `createMarket()` | MARKET_CREATOR_ROLE |
| `pause()` / `unpause()` | Owner |
| `setFeeCollector()` | Owner |

### 有界迭代

没有任何函数会遍历无界集合。Segment trees 提供 O(log N) 操作。Batch 订单数量上限为 MAX_ORDERS_PER_BATCH (1600)，超出部分会自动滚入下一个 batch。结算通过 SETTLE_CHUNK_SIZE = 400 分块执行，因此每次 `clearBatch` 调用的 Gas 成本保持有界。

### 紧急控制

- **Pausable：** owner 可以在协议范围内或单个市场级别暂停市场创建和交易
- **24h auto-cancel：** 未完成结算的市场会自动取消，从而允许完整退款
- **Emergency withdrawal：** 如果 admin 无响应，用户可以通过 timelock 提款

### Anti-Spam / DoS 防护

- 最小 lots 数量防止 dust orders
- 全额抵押锁定让 spam 具有经济成本（资金会锁定到成交或取消）
- **用户级活跃订单上限：** 每个市场 MAX_USER_ORDERS = 20，防止单个地址淹没订单簿
- **Resting order list：** 距离清算价格较远（>20 ticks）的订单会停放在线段树之外，避免 phantom volume 扭曲价格发现，同时仍锁定抵押资产

## Oracle 安全

### Pyth 集成

- 所有价格数据都会通过 Wormhole attestations 在链上进行**密码学验证**
- `parsePriceFeedUpdates` 在链上验证结算价格（窗口内最早的 update）
- **Confidence interval check** 会在价格不确定性超过阈值（默认 1%）时拒绝结算
- Fallback windows 用于处理少见的 Pyth 发布延迟

### 结算安全

- **Finality gate：** 结算需要等待 90 秒 finality period 后才能最终确认
- **Procedural challenge：** 任何人都可以于 finality window 内提交更优的合格 Pyth update
- **Replay protection：** 每个市场只能结算一次

## 交易安全

- **全额抵押：** orderbook trades 由锁定的 USDT collateral 支撑；pool markets 由其配置的 collateral 支撑
- **无杠杆：** 没有 margin，也没有清算风险
- **确定性停盘：** 当 `timeRemaining < batchInterval` 时停止交易，防止最后一秒被利用
- 资金不会被永久锁定，用户始终可以取消订单或提款

## 审计

### 内部审计 v1.2

已完成覆盖所有核心合约的内部安全审计（v1.2）。重点审查范围包括费用拆分逻辑、分块结算、resting order 机制和用户级订单上限。所有 findings 均已处理。完整报告见 `docs/technical/internal-audit-v1.2.md`。

### 世界杯倍数预测 V0 历史审计

已完成针对 2026-06-07 当时状态的世界杯倍数预测 V0 内部 Codex 辅助审计，范围包括持久化、API、管理端表面、前端原型/管理钱包门控，以及迁移 043/044。这不是外部第三方审计。经过加固后，最终复核从 V0 的资金被盗与资金卡死视角给出 PASS 结论。

在上述历史审计之后，生产路由 `/world-cup-multiplier-predictions` 已通过前端钱包、API 和 vault 流程 smoke，使用 vault `0x6859109EEBd3E6A885150d7AF1dE1d3Cd97399f3` 与 tiny smoke event id `2`。验证覆盖 submit prediction、contribute、settle、claim paid、finalize，以及 portfolio/API/UI smoke。完整报告与补充见 `docs/zh/technical/world-cup-multiplier-predictions-v0-audit.md`。

### 静态分析

- Slither static analysis
- Mythril symbolic execution
- Aderyn / 4naly3er additional coverage
- 所有 high/medium findings 均在主网上线前处理
