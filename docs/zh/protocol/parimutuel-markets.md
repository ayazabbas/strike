# 同注分彩池市场

Parimutuel 市场属于 STRIKE 中基于资金池的预测市场形式，与 FBA 订单簿并行存在。订单簿市场更适合活跃交易的二元结果；彩池市场更适合多选事件、周期更长的问题，以及不需要管理限价单的简单买入并持有 exposure。本页介绍标准 USDT/STRIKE 彩池市场；由创建者发起的 BEP20 pools 请参见 [FLAP 代币池](flap-token-pools.md)。

## 它们是什么

一个 parimutuel 市场包含 **2–8 个结果**。交易者选择一个结果，并使用已配置的 pool 抵押资产（通常为 USDT 或 STRIKE）买入该结果的 pool。当前 pool UX 没有订单簿，也没有卖出/cashout；用户持有的是最终 pool 中不可转让的 internal claims。

市场结算后，获胜方获得：

1. 自己在获胜结果中的本金；以及
2. 失败结果 pools 的按比例份额。

失败结果没有收益。如果市场无效或取消，用户可以取回本金。

## 订单簿 vs. Parimutuel

| Feature | FBA 订单簿市场 | Parimutuel 彩池市场 |
|---------|------------------------|--------------------------|
| Best 用于 | 流动性较好的二元市场和主动交易 | 多选事件和简单 directional exposure |
| 结果 | Binary UP/DOWN 或 YES/NO | 2–8 个命名结果 |
| Pricing | 限价单价格发现，$0.01–$0.99 ticks | 基于当前流动性的 pool-implied probabilities |
| Execution | 按统一清算价格定期批量拍卖 | 立即买入选定结果 pool |
| Position management | 到期前可通过订单簿卖出 | 买入并持有，直到领取或退款 |
| 结算 | Pyth、AI 或管理员兜底，取决于市场配置 | Admin、AI 或 Pyth，并带管理员兜底 |
| Payout | 获胜头寸按每 lot 固定价值赎回 | 获胜方按比例瓜分失败方资金池 |

两套系统都通过链上合约完全抵押并结算。订单簿市场使用 USDT；标准彩池市场使用已配置的 pool 抵押资产，例如 USDT 或 STRIKE。

## 市场 Timing

Parimutuel V2 将下注截止时间与事件时间戳拆分：

- **交易 close time** — 用户最后可以买入 pools 的时间。
- **结算 time** — resolver 使用的事件或 reference 时间戳。

这对于需要在事件结束前关闭下注的市场很重要。例如，体育市场可以在开赛时停止买入，但在全场结束后结算。

合约强制要求 `resolutionTime >= tradingCloseTime`。买入及 pool closing 使用 `tradingCloseTime`；管理员、AI 与 Pyth 结算路径使用 `resolutionTime`。

## 结算 Modes

### Admin

市场创建者或管理员将市场结算为获胜结果，或将市场标记为无效。该模式适合受控的内部市场，以及需要人工判断的事件。

### AI

Parimutuel AI resolver 会将已配置的 prompt 发送至 FLAP AI 预言机。AI 提出获胜结果后，挑战/最终确认流程允许在最终确认前进行 review。如果 AI 路径失败或被挑战，市场可以回退到管理员结算。

### Pyth

Parimutuel Pyth resolver 使用市场 `resolutionTime` 的 Pyth price feed，并将价格阈值映射到结果。这支持 “BTC/USD 在 12:00 UTC 落在哪个区间？” 这类多 bucket 的 price-range 市场。

## Pool Pricing

STRIKE 使用 bounded curve presets 将 pool balances 转换为界面显示的概率和预计 payout。默认推荐曲线采用 independent-log preset，使用 `L = 40,000 USDT`；更保守的 `L = 100,000 USDT` preset 也受支持。

前端会显示：

- 每个结果的当前 pool size；
- implied probability；
- 新买入的 projected payout；
- total pool size；
- 用户的 positions 以及领取/退款状态。

## 生命周期

1. **Created** — 配置结果、resolver mode、交易 close time、结算 time、费用及 curve。
2. **Open** — 用户在 `tradingCloseTime` 前买入结果 pools。
3. **Closed** — 不再接受买入；市场等待 `resolutionTime`。
4. **Resolving** — AI/Pyth/管理员结算被请求或提交。
5. **Resolved** — 获胜结果最终确认；获胜方可以 claim。
6. **Invalid/Cancelled** — 用户可以取回本金。

## 合约

标准 parimutuel stack 独立于订单簿 stack：

- `ParimutuelFactory` — 创建市场，并协调生命周期/结算。
- `ParimutuelPoolManager` — 处理买入、pool accounting 及 curve math。
- `ParimutuelVault` — 为标准彩池市场持有已配置抵押资产。
- `ParimutuelRedemption` — 领取获胜 payout，并在无效市场中退款。
- `ParimutuelAIResolver` — 集成 FLAP AI 预言机，并处理挑战/最终确认流程。
- `ParimutuelPythResolver` — 基于 Pyth price-threshold 结算。

参见 [部署](../contracts/deployments.md) 获取实时地址。

## Flap 代币池

FLAP 代币池使用独立 native-token pool stack，服务于由创建者发起、以任意 BEP20 资产抵押的市场。它们沿用同样的 parimutuel 思路：买入一个结果，获胜方瓜分失败方资金池；同时增加 hosted official metadata、链上创建者 prompt、FLAP AI 结算，以及 `0.05 BNB` 创建者 bond。参见 [FLAP 代币池](flap-token-pools.md)。
