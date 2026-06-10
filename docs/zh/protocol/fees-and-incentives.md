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

## 协议 Revenue

所有交易费用都会流向协议费用收集器地址，用于资助 development 与 operations。

## 结算与 Keeper 成本

市场可以由任何人使用有效 Pyth data 无需许可地结算。通常由托管 keeper 执行结算。当前核心 CLOB 合约不支付 resolver bounty。

## Anti-Spam / DoS Prevention

| Mechanism | 目的 |
|-----------|---------|
| **Minimum lot size** | 防止 dust 订单（`MIN_LOTS = 1`，即 `$0.01`） |
| **全额抵押锁定** | 下单存在经济成本，USDT 会锁定到成交或取消 |
| **需要 ERC-20 授权** | 用户下单前必须授权 Vault |
| **用户级活跃订单上限** | 每个市场 `MAX_USER_ORDERS = 20`，防止单个地址刷屏订单簿 |

用户级订单上限通过 `activeOrderCount` mapping 跟踪，并在 `placeOrder`、`placeOrders` 和 `replaceOrders` 中执行。订单取消或结算后会递减该计数。

## Gas 估算

| Action | Est. Gas | Est. Cost |
|--------|----------|-----------|
| Approve 金库 (once) | ~46k | ~$0.001 |
| 提交订单 | ~250k | ~$0.008 |
| 取消订单 | ~100k | ~$0.003 |
| Clear batch / settlement chunk | 取决于 batch size | 取决于网络 |
| 结算市场 | ~300k | ~$0.009 |

*估算仅供参考。订单簿市场的头寸结算通过 `clearBatch` 处理；较大的 batch 可能需要多个 settlement chunks。*
