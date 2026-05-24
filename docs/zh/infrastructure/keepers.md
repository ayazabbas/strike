# Keepers

Keepers 是链下 service，用于调用无需许可的合约函数，让协议持续运行。它们是 **不受信任的**：任何人都可以运行 keeper，而且无论哪个 keeper 提交交易，协议都能正确工作。

## Unified Keeper

STRIKE 运行一个 **unified keeper**：一个 Rust 二进制程序，包含四个并发 tokio task。

| Task | Trigger | 说明 |
|------|---------|-------------|
| **Batch 清算** | Block-driven | 新区块到达时，对活跃市场调用 `clearBatch(marketId)` |
| **市场生命周期** | Sleep-to-boundary | 休眠到市场 expiry，然后触发关闭和结算流程 |
| **结算** | 5-second poll | 三阶段结算：关闭过期市场 → 通过 Pyth 结算 → 90s 后最终确认 |
| **Pruning** | 10-second poll | 清理 resolved、cancelled 与 closed 市场 |

### Batch Clearing

- 通过线段树读取监控待处理订单量
- 如果没有 crossing orders，则跳过清算以节省 Gas
- 对失败执行 Gas estimation 与 exponential backoff
- 结算是原子化的，所有订单都会在批次清算中内联结算，不需要单独的 claim 步骤
- 结算会分块执行：每次 `clearBatch` 调用处理 `SETTLE_CHUNK_SIZE = 400` 个订单

### 结算（三阶段）

1. **Close** — 检测过期市场，并将其转换为 `Closed` 状态
2. **结算** — 从 Hermes 获取 signed Pyth update data，并提交 `resolveMarket()`
3. **Finalize** — 经过 90 秒 finality period 后，调用 `finalizeResolution()`

如果 Pyth data 不可用，admin `setResolved()` 可作为兜底方案。

### Pruning

覆盖 resolved、cancelled 与 closed 市场。它会清理 stale state，使 keeper 的内存使用保持有界。

## 配置

```bash
KEEPER_RPC_URL=https://...
KEEPER_PRIVATE_KEY=0x...
KEEPER_GAS_LIMIT=2000000
```

## Monitoring

- keeper 会记录所有操作，包括时间戳与 Gas 成本
- 对 missed clearing intervals、failed resolutions 与 RPC 错误设置告警
- Health endpoint：`GET /health` 返回 keeper 状态与 last action 时间戳
