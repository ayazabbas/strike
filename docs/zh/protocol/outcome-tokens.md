# 头寸与结算

## Internal Positions（当前 5 分钟市场）

当前 5 分钟市场使用链上跟踪的 **internal positions**，而非 ERC-1155 代币。每个市场有两个方向：**UP** 和 **DOWN**。

### Position Tracking

Positions 存储在一个 mapping 中：

```
positions[user][marketId][side]
```

当你的订单成交后，position 会在内部入账。不会铸造或转账代币。

### 抵押资产

每个 lot 代表 **$0.01 的抵押资产**（LOT_SIZE = 1e16）。当 bid 与 ask 按某个清算 tick 成交时，双方合计提供的抵押资产等于每 lot $0.01，因此完全抵押。

### 交易

Positions 就是你在订单簿中持有的内容：

- **Buying UP at $0.60** = 为一个 UP position 支付每 lot $0.006（隐含 60% 概率）
- **Selling UP at $0.60** = 以每 lot $0.006 卖出你的 UP position
- 等价地，也可以理解为 **buying DOWN at $0.40**（因为 UP + DOWN = 每 lot $0.01）

### 结算（Post-结算）

市场结算后：

- **Winning positions** 以 USDT 按 LOT_SIZE（$0.01）每 lot 支付
- **Losing positions** 没有收益

Batch 结算（抵押资产变化、position crediting）在 `clearBatch` 期间内联完成。市场结算后，获胜 positions 通过 Redemption 合约的 `redeem()` 赎回。

### 示例

你以 tick 60 买入 1000 lots 的 UP（成本：1000 x $0.01 x 60/100 = $6.00）。市场结算为 UP。

- 你的 1000 UP lots 支付 1000 x $0.01 = $10.00
- Profit: $10.00 - $6.00 = $4.00（费用前）

如果市场结算为 DOWN，你的 UP position 价值为 $0。

### Cancellation

如果市场取消（deadline 内没有有效 Pyth update），所有抵押资产都会退回，没有人损失资金。

## ERC-1155 代币（Future 市场 Types）

合约包含完整的 ERC-1155 multi-token system（`OutcomeToken`），用于未来可能需要可转账、可组合代币的市场类型。

### 代币 IDs

代币 IDs 确定性生成，不需要 registry：

- **UP:** `marketId * 2`
- **DOWN:** `marketId * 2 + 1`

### Minting & Merging

对于基于代币的市场，结果代币会以完全抵押的配对形式铸造，并可合并回抵押资产。由于这些代币采用 ERC-1155，它们可以转账，也可以与其他协议组合使用。

该系统目前不用于 5 分钟市场，但合约中已经提供，可供未来通过市场创建时的 `useInternalPositions` flag 启用。
