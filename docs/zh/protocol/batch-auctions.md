# 批量拍卖

STRIKE 使用 **Frequent Batch Auctions (FBA)**，而不是连续撮合订单。这是决定交易如何执行的核心机制。

## 批次如何清算

1. **Accumulate 订单** — 在批次间隔内，交易者可以下单和取消订单。订单会记录在链上，但尚未撮合。

2. **Trigger 清算** — 任何人都可以调用 `clearBatch(marketId)`。该操作无需许可。链上不强制执行批次间隔；keeper 决定清算 cadence。

3. **Find 清算价格** — 合约使用线段树和二分搜索找到清算 tick：
 - Binary search 用于找到满足 cumulative bid >= cumulative ask 的最高 tick
 - Post-search correction: 检查 tick+1，确保 `min(cumBid, cumAsk)` 对应最大匹配量
 - 这会处理 ask 在交叉 tick 超过 bid 的情况

4. **Calculate 按比例成交** — 在清算 tick，如果一侧超额认购，该侧每笔订单获得 `filledLots = (orderLots * matchedLots) / totalSideLots`。

5. **存储结果并推进批次** — 写入 `BatchResult`：清算 tick、匹配手数、买卖总手数和时间戳。批次计数器随后推进，新订单进入下一个批次。

6. **原子化结算** — 所有订单在同一笔交易中内联结算：
 - 已成交抵押资产（按清算价格，而非订单 tick）转入市场池
 - Excess 退款 =（按订单 tick 锁定）-（按清算 tick 计算的 cost），返回所有者
 - 统一费用（20 bps）扣除并发送到协议费用收集器
 - Positions credited（bidder 获得 UP，asker 获得 DOWN）— 用于内部持仓市场；ERC-1155 代币用于基于代币的市场
 - 未成交抵押资产返回所有者
 - GTC 订单会将剩余 lots 滚入下一个批次

## 抵押资产模型（USDT）

双方都锁定 USDT（ERC-20）。用户下单前必须授权金库。Asks 不需要预先持有 positions。

- **Bid** 以 tick 50 买入 10 lots：锁定 `10 × $0.01 × 50/100 = $0.05`
- **Ask** 以 tick 50 卖出 10 lots：锁定 `10 × $0.01 × 50/100 = $0.05`
- 每个 matched lot 合计 = LOT_SIZE（1e16 = $0.01），完全抵押

这比要求 askers 预先持有 positions 更简单，也为双方提供对称的 UX。

## 清算价格结算

所有成交都按**清算 tick**结算，而不是按各自订单的 limit tick。若一笔 bid 以 tick 70 提交，并以 tick 55 清算，则每 lot 只支付 55%，多出的 15% 自动退回。这保证同一 batch 中的所有参与者都以同一公平价格成交。

## 抗 MEV 价格保护

限价单提供内置价格保护。你的订单永远不会以差于你的 tick 的价格成交；如果清算价格超过你的 limit，订单不会成交，抵押资产会退回，或作为 GTC 订单滚入下一个批次。

这与 AMM 式滑点有本质区别。在连续 AMM 中，价格可能在你提交交易和交易执行之间移动。批量拍卖会先收集所有订单，再按单一统一价格一起清算。这里没有“抢跑窗口”，同一批次中的所有人都获得相同价格。

如果你愿意支付更高价格以提高成交概率，可以把订单 tick 设置在距离预期清算价格更远的位置。你的 tick 与实际清算价格之间的差额会自动退回。

## 成交逻辑

| 订单位置 | 结果 |
|---------------|--------|
| Bid at 或 above 清算 tick (non-oversubscribed side) | 完全成交 |
| Ask at 或 below 清算 tick (non-oversubscribed side) | 完全成交 |
| At 清算 tick (oversubscribed side) | 部分成交（按比例） |
| Bid below 清算 tick | 不成交 |
| Ask above 清算 tick | 不成交 |

## 为什么使用批量拍卖？

### vs. 连续撮合

- **No speed advantage** — 同一 batch 中的所有订单平等处理，消除延迟竞争
- **Uniform price** — 所有人获得相同价格，而不是一串逐步推高或压低价格的成交
- **Maker-friendly** — 做市方有完整批次间隔来取消过时报价

### vs. 同注分彩池

- **Real 价格发现** — 价格由 supply 与 demand 决定，而不是由资金池比例决定
- **资本效率高** — 交易者可以在具体价格表达精确观点
- **二级市场** — positions 可以通过订单簿卖单交易

## 休眠订单（价格接近度过滤）

距离上次清算 tick 超过 **PROXIMITY_THRESHOLD = 20 ticks** 的订单会进入**休眠列表**，而不是插入线段树。这可以防止远离市场的订单形成虚假深度并扭曲清算价格。

- 休眠订单会正常锁定抵押资产/代币；它们是真实订单，只是停放在线段树外
- `OrderResting` 事件会触发，且独立于 `OrderPlaced`
- 每次 `clearBatch` 开始时，`pullRestingOrders` 会自动运行，将 in-range 休眠订单拉回线段树（paginated: max **MAX_RESTING_PULL = 200** pulled, max **MAX_RESTING_SCAN = 400** scanned per call）
- 如果 GTC 订单在批次清算后远离价格，会通过 `_tryRollOrCancel` 滚入休眠 list
- 用户可以正常取消休眠订单

## 分块结算

Large batches 会跨多个 `clearBatch` 调用结算：

- **MAX_ORDERS_PER_BATCH = 1600** — v1.1 中从 400 提高
- **SETTLE_CHUNK_SIZE = 400** — 每次 `clearBatch` 调用最多结算 400 笔订单
- 超过 400 笔订单的 batches 需要多次 `clearBatch` 调用才能完成结算
- 预计算成交结果（清算 tick、匹配手数）会在第一次调用中存储，并被后续 chunks 复用，确保跨调用正确性

## 批次溢出

每个 batch 最多包含 **MAX_ORDERS_PER_BATCH (1600)** 笔订单。当一个 batch 已满，新订单会自动 spill into 下一个批次。这限制了 `clearBatch()` 的 Gas 成本，同时保持下单流程顺畅。

## 批次节奏

批次间隔在市场创建时可配置。链上不强制执行该间隔；keeper 决定何时调用 `clearBatch()`。

## 线段树

清算需要知道每个 tick 的累计成交量。朴素做法需要遍历全部 99 个 ticks，链上成本较高。STRIKE 使用**线段树**计算前缀和，并以 O(log N) operations 和最少存储写入找到清算 tick。
