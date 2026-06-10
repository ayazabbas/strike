# 设计决策

关键架构选择及其理由。

## 选择 FBA 而非连续订单簿

**决策：** 使用 Frequent Batch Auctions，而不是连续撮合。

**原因：** 于 EVM 上，连续订单簿会产生 MEV 抽取机会：bots 会争抢时间优先级、进行 sandwich trades，并 front-run 大额订单。FBA 消除了批次内的时间优先级，并让所有人获得相同的清算价格。代价是每个 batch 有 60 秒延迟（可配置），但对于持仓时间通常以分钟计、而不是以毫秒计的预测市场来说，这是可以接受的。

## 选择原子化内联结算而非 Claim-Based 结算

**决策：** `clearBatch()` 在单笔交易中原子化结算所有订单。不需要单独的 claim step。

**原因：** 单笔交易结算消除了单独 claim step 带来的 UX 摩擦。用户会立即收到成交、超额退款和铸造的 positions。Gas 成本随订单数量线性增长，并受到每次 `clearBatch` 调用 SETTLE_CHUNK_SIZE = 400、MAX_ORDERS_PER_BATCH = 1600 的限制。大型 batch 会通过多次 `clearBatch` 调用完成结算，并使用预计算成交确保正确性。

## 选择 Pyth `price` 而非 `ema_price`

**决策：** 使用 spot `price` 进行结算，而不是指数移动平均。

**原因：** Spot price 提供清晰、直接的市场语义。一个询问“BTC 在时间 T 是否高于 $X？”的市场，应当根据时间 T 的实际 price 结算，而不是根据平滑后的平均值结算。EMA 会引入滞后，使结算价格偏离交易者在交易所观察到的价格。

## 最后一个 Batch 停止交易

**决策：** 当 `timeRemaining < batchInterval` 时停止接受订单。不使用中点锁定。

**原因：** 原始 PoC 使用中点锁定规则，即 5 分钟市场在 2.5 分钟时停止交易。这一规则较为随意，也浪费了半个市场周期。新规则更简单，并最大化交易时间：订单簿保持开放，直到最后一个完整 batch 可以清算，然后停止。该规则确定且公平。

## 使用 ERC-1155 表示结果代币

**决策：** 使用多代币 ERC-1155，而不是为每个结果部署一个 ERC-20。

**原因：** 每个市场部署两个 ERC-20 合约成本较高，并会带来地址管理开销。ERC-1155 使用单个合约和确定性的 token IDs（`marketId * 2` 表示 YES，`marketId * 2 + 1` 表示 NO）。这样部署更便宜、记账更简单，同时 tokens 仍然可以自由转账。

> **注意：** 当前 5 分钟市场为了效率使用 internal positions（`useInternalPositions = true`）。ERC-1155 token 系统会保留给未来需要可转账 tokens 的市场类型，例如更长周期的市场或二级市场交易。

## 使用线段树进行价格聚合

**决策：** 使用 segment tree，而不是朴素迭代或 Fenwick tree。

**原因：** 清算需要找到累计 bid 与 ask volume 交叉的位置。对 99 个 ticks 进行朴素迭代需要 O(99) 次 storage reads。Segment tree 对更新与 prefix sum queries 都提供 O(log 99) ≈ O(7) 的操作复杂度。Clober 的 LOBSTER research 验证了这种方法适用于链上 orderbooks，通过 segmented trees 最小化 SSTORE operations。

## 结算中的 Finality Gate

**决策：** 使用带 90 秒 finality period 的两步结算。

**原因：** BSC 上的单交易结算理论上可能被重组，从而改变市场结果。通过拆分为 `resolveMarket()`（提交数据）和 `finalizeResolution()`（等待 90 秒后执行），可以确保结算价格在经济意义上最终确定。Finality period 内的 challenge window 允许任何人提交更优（更早）的 Pyth update，从而强制执行确定性的 "earliest update wins" 规则。

## 默认公开提交

**决策：** 订单默认公开链上提交；私有提交为可选项。

**原因：** 私有交易通道（BEP-322、NodeReal bundles）会引入基础设施依赖和信任假设。公开提交是最简单、可组合性最高的基线。需要 MEV 保护的专业交易者可以选择私有 channels，协议在两种方式下都会正确运行。

## 选择 BNB Chain 而非 opBNB

**决策：** 部署于 BSC 主网，而非 opBNB L2。

**原因：** BSC 上的 Gas 已经很便宜（0.05 gwei 时约 $0.008/order）。opBNB 会增加 bridge friction（用户必须从 BSC bridge）、生态更小、收取不可忽略的 Pyth fees，并且缺少 BSC 已记录的 MEV 基础设施（BEP-322、bundle APIs）。边际 Gas 节省不足以抵消 UX 和生态方面的取舍。
