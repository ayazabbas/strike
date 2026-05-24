# 预言机结算

STRIKE 支持 **Pyth 价格源**、**FLAP AI 预言机**以及管理员/兜底结算，具体取决于市场类型。本页重点介绍 Pyth 与 AI 流程。

## 结算 Methods

| Method | 使用场景 | Source |
|--------|----------|--------|
| **Pyth 价格源** | Price 市场（“将 BTC be above $X?”） | Cryptographically signed price data |
| **FLAP AI 预言机** | 由 AI 结算的市场，包括 FLAP 代币池 | LLM/tool reasoning，并在可用时使用 proof data |
| **Admin / 兜底** | Curated sports/事件 pools，以及 challenged/failed AI 流程 | 协议管理员 action |

---

## Pyth Price Feed 结算

Price 市场通过 Pyth 网络预言机价格源结算。无需人工干预、主观仲裁或治理投票。

## 结算 Rule

每个市场都有 expiry 时间戳 `T`。结算使用 **`publishTime` 位于 `[T, T+Δ]` 内的最早 Pyth price update**，其中 `Δ` 是协议参数（默认 60 seconds）。

- resolver 从 Pyth 的 Hermes historical API 获取 signed update data
- 合约在链上使用 `parsePriceFeedUpdates(updateData, priceId, T, T+Δ)` 验证
- Pyth 返回匹配该 window 的 update；challengers 可以提交更早 `publishTime` 的 update 来替换它
- 结算使用 `price` 字段（不是 `ema_price`），即 spot price，以保持清晰的市场语义

## Confidence Interval Check

Pyth 每次 price update 都会发布 **confidence interval**。如果 confidence 相对 price 过宽，结算会被拒绝：

```
Reject if: conf > confThresholdBps × |price| / 10000
```

默认 threshold 为 1%（100 bps）。这可以防止使用不可靠 price data 结算。

## 兜底 Windows

如果 `[T, T+Δ]` 内没有 Pyth update：

- resolver 可以尝试 `[T, T+2Δ]`，然后 `[T, T+3Δ]`，最多到 `K×Δ`
- 这可以处理 Pyth publishing 延迟的少见情况
- 如果最大 window 内仍没有有效 update，市场取消

## Finality Gate

结算不会即时完成：

1. Resolver 使用 Pyth update 调用 `resolve()`，设置 `pendingResolution`，市场进入 `Resolving`
2. 协议等待 **90 秒 finality period**（`FINALITY_PERIOD = 90 seconds`）
3. 在此 window 内，任何人都可以提交 **alternative** Pyth update；这个 update 必须具有更早的有效 `publishTime`，且会**改变结果**（例如从 UP 翻转为 DOWN）
4. 最终确认窗口结束后，调用 `finalizeResolution()`，市场进入 `Resolved` 状态
5. **管理员兜底:** 紧急情况下，管理员可以调用 `setResolved()` 跳过两步流程

这种“流程性挑战”机制确保 deterministic rule（earliest update wins）得到执行，即使第一个 resolver 提交了次优 update。

## Resolver Incentives

- 结算**无需许可**，任何人都可以调用 `resolveMarket()`
- 协议运行 backstop keepers，以确保及时结算
- 如果 24 小时内无人结算，市场会自动取消，所有资金都会退回

## Why Pyth?

- **Pull 预言机** — 不需要持续链上推送价格；只在结算时提交一次 update
- **~400ms update cadence** — 预言机网络层面的更新节奏
- **Cryptographic verification** — signed data 在链上验证，不依赖某个 EOA
- **Historical data 可用** — Hermes API 提供过去时间戳的 signed updates
- **Low cost** — BSC 上 update 费用很低（默认 1 wei）

---

## AI 预言机结算

AI 市场通过 **FLAP AI 预言机**结算；预言机会评估已配置的 prompt 并返回一个结果选项。不同市场系列使用不同的 resolver 合约，包括 `AIResolver`、`ParimutuelAIResolver` 与 `NativeTokenPoolAIResolver`。一般生命周期如下：

1. **Request** — 市场 expiry 时，keeper 调用 `resolveMarket()`，将 prompt 发送到预言机
2. **AI/tool reasoning** — 预言机 backend 使用该市场 family 的 STRIKE/FLAP 配置评估 prompt
3. **Callback** — 预言机使用 numeric 结果 choice 回调
4. **Liveness window**（30 minutes）— proposed 结算可被挑战
5. **Finalisation** — 如果无人挑战，任何人都可以调用 `finalise()` 来结算市场

### 挑战 Mechanism

在 30 分钟 liveness window 内，AI proposal 可通过提交已配置的挑战 bond 被挑战。被挑战的市场会进入管理员 review；管理员可以根据 resolver rules 确认原结果或覆盖结果。Bond sizes/rewards 由具体合约决定。

### IPFS Verification

AI 结算证明数据会在可用时通过索引器或预言机/provider 合约暴露。可用性和具体字段取决于 resolver 路径与市场系列。

完整 details 参见 [AI 市场](ai-markets.md)。
