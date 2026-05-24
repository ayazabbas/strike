# 费用与激励

## 交易费用

STRIKE 使用 **uniform fee model**，买卖双方按 **50/50 buyer-seller split** 分摊费用：

| Parameter | Rate | Description |
|-----------|------|-------------|
| **总费用** | 20 bps (0.20%) | 在买方和卖方之间平均分摊 |
| **Buy-side 费用** | `floor(fee / 2)` | 从买方成交抵押资产中扣除 |
| **Sell-side 费用** | `ceil(fee / 2)` | 从卖方 USDT payout 中扣除 |

- 不区分 maker/taker，双方各支付一半费用
- 整数 rounding 产生的额外 wei 归协议所有（sell side 支付 `ceil`）
- 费用会随 batch 清算原子化扣除，并内联完成
- 所有费用进入 `protocolFeeCollector` 地址
- `clearingBountyBps` 存在且可由管理员配置，但当前设置为 0

## 协议 Revenue

所有交易费用都会流向协议费用收集器地址，用于资助 development 与 operations。

## Resolver Bounty

市场可以由任何人使用有效 Pyth data 无需许可地结算。resolver bounty mechanism 可通过 FeeModel 配置，但当前设置为 0。

## Anti-Spam / DoS Prevention

| Mechanism | 目的 |
|-----------|---------|
| **Minimum lot size** | 防止 dust 订单（MIN_LOTS = 1，即 $0.01） |
| **MAX_ORDERS_PER_BATCH** | 限制单个 batch 的结算成本 |
| **SETTLE_CHUNK_SIZE** | 允许大型 batches 分块结算 |
| **Resting orders** | 防止远离市场价格的订单扭曲清算树 |
| **Finality windows** | 给确定性结算提供挑战机会 |

## Gas 估算

| Action | Est. Gas | Est. Cost |
|--------|----------|-----------|
| Approve 金库 (once) | ~46k | ~$0.001 |
| 提交订单 | ~250k | ~$0.008 |
| 取消订单 | ~100k | ~$0.003 |
| Clear batch (原子化) | ~2.0M | ~$0.063 |
| 结算市场 | ~300k | ~$0.009 |

*基于 BNB ≈ $628。订单簿市场的头寸结算已包含于 Clear batch 流程；通常不需要单独的 claim transaction。*
