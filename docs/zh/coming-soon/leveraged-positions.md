# 杠杆 Positions

> **状态：Coming Soon** - 该功能仍处于设计阶段。

## 概览

Strike 将在短周期市场（例如 5 分钟 BTC/USD）中支持**带杠杆的二元 positions**，让交易者无需投入更多初始资金即可放大敞口。

杠杆由**协议流动性 vault** 提供支持，类似 Hyperliquid 的 HLP 或 Jupiter 的 JLP。Vault 存款人提供杠杆交易所需的额外抵押资产，并从交易费用和交易者亏损中获得收益。

## 工作方式

### 无杠杆（当前）

交易者以 tick 50（$0.50）买入 UP：

- 每 lot 支付 **$0.50**
- 如果 UP 胜出，获得 **$1.00**（本金回报 2x）
- 如果 DOWN 胜出，损失 **$0.50**

### 使用 3x 杠杆

交易者以 tick 50、3x 杠杆买入 UP：

- 每 lot 支付 **$0.50**（与之前相同）
- Vault 额外锁定每 lot **$1.00** 作为 backing
- 如果 UP 胜出，获得 **$1.50**（vault 提供额外的 $0.50）
- 如果 DOWN 胜出，损失 **$0.50**（vault 保留其锁定资金并收取 premium）

交易者的风险和收益都会被放大，但最大损失仍限制在其抵押资产内，不会发生清算。

### 为什么二元市场让这件事更简单

与可能引发连环清算的 perpetual futures 不同：

- **结果有界** - 二元市场只会结算为 0 或 1。Vault 每 lot 的最大负债在下单时已知
- **周期短** - 资金锁定时间以分钟计，而不是无限期。Vault utilization 周转很快
- **无 funding rates** - Positions 会自然到期，不需要持续再平衡

## Strike Liquidity Vault (SLV)

### 面向存款人

- 将 USDT 存入 SLV，获得 SLV LP tokens
- 收益来源包括：
  - **Leverage premiums** - 对杠杆 positions 收取的费用
  - **交易者亏损** - 当杠杆交易者亏损时，vault 保留其抵押资产和未解锁的 backing
  - **交易费用** - 协议费用分成
- 可随时提款（受 utilization 影响；如果 vault 资金锁定在活跃市场中，提款可能需要部分延迟到市场结算后）

### 面向交易者

- 下单时选择杠杆倍数（2x、3x、5x、10x）
- 除标准交易费用外，还需支付 **leverage premium**，该费用随倍数以及 vault utilization 变化
- 最大损失始终是自己的抵押资产，没有清算风险
- Payouts 会在市场结算时自动计算并结算

## Vault 风险管理

Vault 内置以下保护措施：

| Parameter | Purpose |
|---|---|
| **Max leverage** | 根据市场类型和周期设置每个市场的上限（例如 10x） |
| **Max vault exposure per market** | 限制单个市场可锁定的 vault 资金比例 |
| **Utilization-based pricing** | Vault utilization 越高，leverage premium 越高；当资金稀缺时自然抑制需求 |
| **Diversification** | Vault 敞口分散在多个并发 5 分钟市场中，单个市场结果会被平均化 |

### 为什么 Vault 长期占优

短周期二元市场对资金池有统计优势：

- 散户在快速方向性下注中通常输多赢少
- Leverage premium 无论结果如何都会提供确定收入
- 高周转率（5 分钟周期）让大数定律更快发挥作用
- Vault 分散在多个并发市场中，variance 会被平滑

这与 HLP 于 Hyperliquid 上持续盈利的机制相同。

## Premium Pricing

Leverage premium 可以按不同方式设计：

**Option A - 按倍数收取固定费用：**

| Leverage | Premium |
|---|---|
| 2x | 1% of position |
| 3x | 2% |
| 5x | 4% |
| 10x | 8% |

对交易者来说简单且可预测。

**Option B - 动态定价（基于 utilization）：**

Premium 随 vault utilization 变化；vault 闲置时便宜，重度使用时昂贵。类似 Aave/Compound 的 interest rate curves。

```
premium = baseFee × leverage × utilizationMultiplier
```

资本效率更高，但对交易者来说可预测性较低。

## 示例场景

**Market：** BTC 在 5 分钟后是否高于 $84,500？（tick 50 = $0.50）

| Trader | Action | Leverage | Pays | Vault Locks | If UP Wins | If DOWN Wins |
|---|---|---|---|---|---|---|
| Alice | Buy UP | 1x | $50 | $0 | +$50 | -$50 |
| Bob | Buy UP | 3x | $50 | $100 | +$100 | -$50 |
| Carol | Buy DOWN | 5x | $50 | $200 | -$50 | +$200 |

- Bob 为 3x 杠杆支付 2% premium（$1）
- 如果 UP 胜出：Bob 获得 $150（$50 collateral + vault 提供的 $100）。Vault 因 Bob 亏损 $100，但保留 Carol 的 $50 以及 $200 locked backing
- Vault 的净 P&L 取决于所有交易者和市场的聚合结果

## 对比

| | Strike Leveraged | Perp DEX (Hyperliquid) | Binary Options (traditional) |
|---|---|---|---|
| Max loss | 仅抵押资产 | 抵押资产（清算） | 仅抵押资产 |
| Liquidation risk | 无 | 有 | 无 |
| Duration | 固定（5 min） | 无限期 | 固定 |
| Funding rates | 无 | 持续 | 无 |
| Vault model | SLV（类似 HLP） | HLP | House/bookmaker |
| Settlement | 链上、确定性 | Mark price | 通常链下 |

## 路线图

- [ ] SLV vault contract（deposit/withdraw/LP tokens）
- [ ] 下单时支持 leverage parameter
- [ ] Premium pricing model（固定或动态）
- [ ] Vault risk management（exposure caps、utilization curve）
- [ ] Frontend：leverage selector + P&L preview
- [ ] Backtesting：基于历史 5-min data 模拟 vault P&L
- [ ] BSC 测试网部署
