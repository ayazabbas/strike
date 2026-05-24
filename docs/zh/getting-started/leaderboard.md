# 排行榜

查看你相对其他 STRIKE 交易者的排名。

## Rankings

排行榜跟踪两个指标：

- **PNL (Profit and Loss)** -- 你的交易净收益。PNL 最高的交易者盈利最多。
- **Volume** -- 你的交易总 USDT 价值。Volume 越高，说明交易越活跃。

## Time Periods

可以按不同时间窗口筛选排行榜：

| Period | What It Shows |
|--------|--------------|
| **24H** | Last 24 hours |
| **7D** | Last 7 days |
| **30D** | Last 30 days |
| **All** | All time |

切换不同周期，可以查看当前表现最强的交易者，也可以查看长期保持盈利的交易者。

## PNL 如何计算

你的 PNL 基于**已结算市场的 realized gains**。当市场结算时：

- 如果你持有获胜方向，gain 为每个代币 **$1.00 减去你的 purchase price**。
- 如果你持有失败方向，loss 为每个代币的 **purchase price**。
- 到期前卖出代币产生的 profits 与 losses 也会计入。

只有已结算市场会计入排行榜 PNL。未平仓持仓要等市场结算后才会纳入统计。

## 设置用户名

默认情况下，排行榜 entry 会显示截断的钱包地址。领取用户名：

1. 进入你的 profile 或排行榜 page。
2. 选择一个用户名。
3. 签署一条消息，验证你拥有该钱包（EIP-191 signature；应用会自动处理，你只需确认 prompt）。

用户名一旦设置即永久有效，请谨慎选择。它会显示在排行榜，以及展示你交易 activity 的其他位置。
