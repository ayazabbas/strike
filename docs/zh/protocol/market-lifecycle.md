# 市场生命周期

STRIKE 有两套生命周期模型：FBA 订单簿市场以及 parimutuel 彩池市场。订单簿市场会经历以下状态：

```
Open → Closed → Resolving → Resolved
                          ↘ Cancelled
```

## States

### Open

- 订单簿接受订单（下单、取消）
- Batch 清算按已配置间隔运行（默认 60 秒）
- **Transition:** 当 `block.timestamp + batchInterval >= expiryTime` 时自动进入 `Closed`

### Closed

- **不再接受新订单** — 最终 batch 已完成清算
- 现有订单仍可取消，用于释放抵押资产
- **Transition:** 任何人通过 `resolve()` 提交有效 Pyth 结算后进入 `Resolving`

### Resolving

- 已使用 signed Pyth price data 提交结算
- **Finality gate:** 协议等待 90 秒 finality period（`FINALITY_PERIOD = 90 seconds`）后才能最终确认
- **挑战 window:** 在此期间，任何人都可以提交会**改变结果**的 alternative Pyth update；合约会在结算 window 内确定性地选择最早的有效 `publishTime`
- **Transition:** finality window 结束后调用 `finalizeResolution()`，进入 `Resolved`

### Resolved

- 结果最终确定（UP 或 DOWN）
- 获胜头寸按每 lot $0.01 自动支付
- 失败头寸价值归零

### Cancelled

- 如果在最大结算 window（24h）内没有提交有效 Pyth update，则触发取消
- 如果结算时 confidence interval 超过 threshold，也会触发取消
- 所有抵押资产退回

## 管理员兜底

管理员可以调用 `setResolved()` 作为兜底，跳过两步式结算/最终确认流程。它只应在紧急情况下使用，例如 Pyth 价格源故障或结算卡住。

## Timeline（5 分钟市场，60 秒批次间隔）

```
0:00    Market created, strike price captured from Pyth
0:00    Orderbook open — batches clear every 60 秒
        ...
4:00    Last batch clears (< 60 秒 remaining → trading halts)
5:00    Expiry timestamp reached — market enters Closed
5:00+   Resolver submits Pyth update for [T, T+60 秒] window → resolve()
        Finality period (90 seconds)
        Challenge window open during finality period
~6:30   finalizeResolution() → market Resolved
6:30+   Winning positions settled automatically
```

## Parimutuel Pool 生命周期

Parimutuel 市场使用独立的 pool 生命周期：

```
Open → Closed → Resolving → Resolved
                    ↘ Invalid/Cancelled
```

### Open

- 用户可以买入任意结果 pool。
- Buying 在 `tradingCloseTime` 前开放。
- Pool probabilities 与 projected payouts 会随着用户买入而更新。

### Closed

- 不再接受新买入。
- 市场等待 `resolutionTime`，随后 resolver paths 才能最终确认结果。
- 这种拆分允许 betting 在事件本身结束前关闭。

### Resolving

- Admin、AI 或 Pyth 结算确定获胜结果。
- AI 市场可能先经历 request/proposal/挑战/finality，再进入确认。
- Pyth 市场在 `resolutionTime` 评估已配置的 feed/thresholds。

### Resolved

- 获胜结果最终确定。
- 获胜方领取本金，以及失败方资金池的按比例份额。

### Invalid / Cancelled

- 当市场无法公平结算或被明确标记为无效时使用。
- 用户取回本金。
