# 安全

## 智能合约安全

### Reentrancy 防护

需要防护的外部状态变更函数使用 OpenZeppelin `ReentrancyGuard`，并遵循 checks-effects-interactions。

### 访问控制

| Function | Access |
|----------|--------|
| `placeOrder()` / `cancelOrder()` | 余额/授权充足的任意用户 |
| `clearBatch()` | 任意用户 |
| `resolveMarket()` | 提供有效 Pyth data 并支付 update fee 的任意用户 |
| `finalizeResolution()` | finality 后的任意用户 |
| `redeem()` | 符合条件的 token/position holder |
| `createMarket()` | `MARKET_CREATOR_ROLE` |
| `pauseFactory()` / lifecycle admin actions | `ADMIN_ROLE` |
| `setProtocolFeeCollector()` | FeeModel 的 `DEFAULT_ADMIN_ROLE` |

### 有界迭代

Segment tree 提供 O(log N) 的价格层级操作。订单数量和 resting-order scan 都有上限。Batch settlement 会分块执行（`SETTLE_CHUNK_SIZE = 400`），使每次 `clearBatch` 调用的 gas 保持有界。

### 紧急控制

- 授权 operator 可以 halt/resume 或 deactivate 市场。
- 无法结算的市场可以通过配置的 fallback path 取消，以便退款。
- Vault emergency mode 有 timelock，之后才允许 emergency withdrawal。

### Anti-Spam / DoS 防护

- 最小 lot size 防止 dust 订单。
- 全额抵押锁定为 spam 创造资金成本。
- 每个市场 `MAX_USER_ORDERS = 20`，防止单一地址刷屏订单簿。
- 远离清算价的 resting orders 会停放在 active segment tree 外，但仍锁定抵押资产。

## Oracle 安全

### Pyth 集成

- Pyth update data 在链上验证。
- `parsePriceFeedUpdates` 读取结算窗口内的价格，不依赖预先更新的链上价格。
- Confidence check 会拒绝不确定性过高的 update。
- Fallback windows 用于处理少见的 Pyth 发布延迟。

### 结算安全

- 首次有效提交会启动 90 秒 finality window。
- finality 期间，只有更早且会改变结果的有效 update 才能 challenge。
- finality window 结束后，finalization 是 permissionless 的。
- 每个市场只能 finalize 一次。

## 交易安全

- 订单簿交易由锁定 USDT 或锁定仓位全额抵押。
- Pool markets 由其配置的抵押资产支持。
- 没有 margin 或 liquidation 机制。
- 市场 active 时，用户可以取消 open orders。

## 审计

### Internal Audit v1.2

内部安全审计 v1.2 覆盖了核心合约，包括费用拆分逻辑、chunked settlement、resting orders 和用户级订单上限。见 [Internal Audit v1.2](internal-audit-v1.2.md)。

### World Cup Multiplier Cross-Event Ticket Internal Review

内部 Codex-assisted review 覆盖了 World Cup Multiplier 跨事件 Prediction Ticket refactor。这不是外部第三方审计。见 [World Cup Multiplier Cross-Event Ticket Internal Review](world-cup-multiplier-predictions-v0-audit.md)。
