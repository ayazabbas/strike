# PythResolver.sol

处理 Pyth 预言机集成，用于确定性市场结算。

## `resolveMarket(marketId, updateData)`

1. 验证市场处于 `Closed` 状态。
2. 通过 Pyth 合约调用 `parsePriceFeedUpdates(updateData, priceId, T, T+Δ)`。
3. **Confidence check:** 如果 `conf > confThresholdBps × |price| / 10000`，则 revert。
4. 使用解析出的 price 与 publish time 设置 `pendingResolution`。
5. 记录 resolver 地址，用于 bounty payment。

## `finalizeResolution(marketId)`

1. 验证距离 `resolveMarket` 调用已至少经过 90 seconds（FINALITY_PERIOD）。
2. 检查最终确认窗口内是否有 challenger 提交了更优（更早）的 update。
3. 判断结果: price > STRIKE 时 YES 胜出；price ≤ STRIKE 时 NO 胜出。
4. 将市场转换为 `Resolved`。
5. 支付 resolver bounty。

## Challenges

挑战在 `resolveMarket()` 内部处理。在最终确认窗口内，任何人都可以再次调用 `resolveMarket()`，并提供备用 Pyth update data。该 update data 必须包含位于 `[T, T+Δ]` 窗口内且更早的 `publishTime`。只有当新 update 会改变市场结果（即把结算从 YES 翻转为 NO，或从 NO 翻转为 YES）时，挑战才会被接受。挑战被接受后，新的 update 会替换 pending 结算，challenger 成为新的 resolver 并获得 bounty。合约没有单独的 `challengeResolution()` 函数。

## 配置

| Parameter | 默认 | Description |
|-----------|---------|-------------|
| `Δ (delta)` | 60 秒 | expiry 后的结算窗口 |
| `maxDelta` | 300s (5×Δ) | 最大兜底窗口 |
| `confThresholdBps` | 100 (1%) | 最大 confidence/price 比率 |
| `finalityPeriod` | 90s | 等待最终确认的时间 |

## 管理员兜底: `setResolved()`

管理员可以通过 MarketFactory 调用 `setResolved(factoryMarketId, outcomeYes, settlementPrice)`，直接结算市场，绕过两步式提交与最终确认流程。这是安全兜底，用于 Pyth data 不可用或正常结算流程卡住的情况。

## Admin Transfer

两步管理员转移: `setPendingAdmin(address)` → `acceptAdmin()`。该流程可防止意外丢失管理员权限。

## 事件

```solidity
event ResolutionSubmitted(uint256 indexed factoryMarketId, int64 price, uint256 publishTime, address indexed resolver);
event ResolutionChallenged(uint256 indexed factoryMarketId, int64 newPrice, uint256 newPublishTime, address indexed challenger);
event ResolutionFinalized(uint256 indexed factoryMarketId, int64 price, bool outcomeYes, address indexed finalizer);
```
