# 工作原理

## 交易方式

STRIKE 目前有三种实时市场形态：

- **FBA 订单簿市场** — 使用限价单、batch-auction 撮合、主动交易，并支持到期前卖出头寸的二元市场。
- **Parimutuel 彩池市场** — 面向 2–8 个结果的彩池市场，用户直接买入某个结果，结算后获胜方瓜分失败方资金池。
- **FLAP 代币池** — 由创建者发起的代币 pool，使用 BEP20 抵押资产，并通过链上 prompt 交由 FLAP AI 结算。

如果你需要价格发现和主动交易，可以使用订单簿市场；如果你需要简单的多结果 pool，可以使用标准 parimutuel 市场；如果创建者想发起一个由 AI 结算、以 BEP20 代币抵押的代币数据市场，可以使用 FLAP 代币池。

## 订单簿交易循环

STRIKE 运行连续的短周期预测市场（默认 5 分钟）。每个市场都会提出一个简单问题：

> **将 BTC/USD be above $X at time T?**

其中 `$X` 指 STRIKE price（市场创建时从 Pyth 捕获），`T` 指 expiry 时间戳。

如果市场已配置，也可以通过 **FLAP AI 预言机**结算。公开 FLAP 代币池目前针对可从 Ave 支持的数据中解析的代币数据 prompt 优化，例如价格、流动性、成交量、FDV 或市值。

交易者通过在订单簿下单表达观点：

- **Buy UP**：如果你认为到期时价格会高于 STRIKE
- **Buy DOWN**：如果你认为到期时价格会低于 STRIKE

## Step by Step

1. **市场 opens** — 使用 STRIKE price 与 expiry 创建新市场，订单簿开始接受订单。

2. **充值 USDT** — 向你的 STRIKE 钱包充值 USDT。Approvals 与 Gas 会自动处理。

3. **提交订单** — 交易者以期望价格（$0.01–$0.99）提交限价单。价格为 $0.70 的 UP position 表示“价格高于 STRIKE 的概率为 70%”。下单时，USDT 抵押资产会自动锁定。

4. **Batches 清算** — 系统定期将所有待处理订单按统一清算价格撮合。如果 bid 与 ask 交叉，系统会找到使匹配量最大化的清算价格。超额一侧按比例部分成交。结算在同一笔交易中原子化完成：你的 position 会被记录，任何多余抵押资产都会自动退回。

5. **交易 halts** — 当距离 expiry 不足一个批次间隔时，订单簿停止接受新订单。最终批次照常清算。

6. **市场结算** — expiry 后，任何人都可以提交 signed Pyth price update 来结算市场。合约会以密码学方式验证该 update，并确定结果。

7. **Redeem winnings** — 获胜头寸按完整价值支付，失败头寸没有收益。

## FBA 有什么不同？

在连续订单簿中，最先到达的订单获得优先权，这会制造速度竞争与 MEV 抽取。在**频繁批量拍卖**中：

- 批次窗口内的所有订单被平等处理（批次内没有时间优先级）
- 所有人获得同一清算价格（uniform price）
- 超额一侧按比例成交（公平的部分成交）
- 做市方有时间在下一个批次前取消过时报价

这与传统证券交易所开盘/收盘拍卖采用的机制类似，只是被改造用于链上预测市场。

## Parimutuel Pool 循环

Parimutuel 市场不使用订单簿。每个市场有 2–8 个命名结果，并为每个结果设置一个 pool。

1. **市场 opens** — 配置结果、resolver mode、交易 close time、结算 time、费用及 curve。
2. **选择结果** — 交易者选择他们认为会获胜的结果，并使用 USDT 买入该资金池。
3. **Pool odds update** — 随着流动性在不同结果 pool 之间变化，界面会更新显示概率和预计 payout。
4. **交易 closes** — 在 `tradingCloseTime` 停止买入。该时间可以早于事件的最终 `resolutionTime`。
5. **市场结算** — 管理员、AI 或 Pyth 结算会选择获胜结果，或者将市场标记为无效。
6. **Claim 或退款** — 获胜方领取本金和失败方资金池的按比例份额。无效市场退还本金。

阅读完整 [Parimutuel 彩池市场](../protocol/parimutuel-markets.md) 指南，了解 timing、payout 及 resolver details。

## FLAP Token Pool 循环

FLAP 代币池是由创建者发起的彩池市场，使用创建者选择的 BEP20 代币作为抵押资产。

1. **Creator defines 市场** — 定义抵押资产代币、结果、timing 及 prompt。
2. **Official metadata 上传** — STRIKE 在链上 create transaction 中托管经过哈希校验的元数据。
3. **用户交易** — 交易者使用选定代币买入结果 exposure。
4. **FLAP AI 结算** — resolver 在结算 time 使用链上 prompt。
5. **挑战 window** — AI proposals 有 30 分钟挑战窗口。
6. **Claim 或退款** — 最终确认获胜方后可领取；无效或取消的市场可退款。

阅读完整 [FLAP 代币池](flap-token-pools.md) 指南，了解 prompt、抵押资产和生命周期 details。
