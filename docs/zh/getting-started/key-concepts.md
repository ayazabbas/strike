# 核心概念

## 市场 Types

STRIKE 支持三种实时市场形态：

- **FBA 订单簿市场** — 使用限价单、批量清算和主动 position management 的二元 UP/DOWN 或 YES/NO 市场。
- **标准同注分彩池市场** — 2–8 个结果的市场，用户买入结果池，获胜方瓜分失败方资金池。
- **FLAP 代币池** — 由创建者发起的 BEP20 抵押资产 pools，通过链上 prompt 交由 FLAP AI 结算。

## 订单簿 Positions

每个订单簿市场都有两个方向：**UP** 和 **DOWN**。当前 5 分钟市场使用链上跟踪、完全抵押的 **internal positions**。（合约也包含用于未来市场类型的 ERC-1155 代币系统，但 5 分钟市场不使用它。）

- **Filling:** 当你的订单成交后，position 会在内部入账。Positions 按用户、市场及 side 分别记录。
- **结算:** 结算后，winning positions 按每 lot $0.01 自动支付。Losing positions 价值归零。

由于 UP + DOWN 始终等于每 lot $0.01 的抵押资产，订单簿价格代表隐含概率。一个以 $0.65 交易的 UP position 表示结果发生的隐含概率为 65%。

## Ticks

订单簿价格使用 **tick system**：从 $0.01 到 $0.99 共 99 个离散价格档位，精度为 1 cent。你可以在任意 tick 下单。

## Batch Intervals

订单簿不会连续撮合订单。订单会先累积，再在周期性批次中撮合。清算节奏由 keeper 决定，链上不强制执行间隔。

## Clearing Price

每个存在交叉订单（bid >= ask）的批次都会产生一个**统一清算价格**。这个 tick 会最大化总匹配量。该批次中的所有成交都按此清算价格结算，而不是按各订单的限价 tick 结算。任何多余抵押资产（订单 tick 与清算 tick 的差额）都会自动退回。

## 按比例 Fills

如果清算价格处订单簿某一侧的数量多于另一侧，超额一侧会**按比例**成交，即按每笔订单的 size 分配成交量。批次内没有单笔订单优先权。

## 订单 Types

| Type | Behavior |
|------|----------|
| **GoodTilCancel (GTC)** | 留在订单簿中，直到成交或被所有者取消 |
| **GoodTilBatch (GTB)** | 仅对下一个批次有效；如果未成交，清算后自动过期 |

## 抵押资产

所有订单都使用 **USDT**（ERC-20）完全抵押。用户下单前必须授权金库合约。下 bid（buy UP）时，你会按 tick price 锁定相应 USDT。下 ask（buy DOWN）时，也会按 `(100 - tick)` 对应比例锁定 USDT。双方都锁定 USDT；ask 不需要预先持有 positions。每个 lot 代表 $0.01 抵押资产（LOT_SIZE = 1e16）。没有 leverage 或 margin。

## 同注分彩池

Parimutuel 市场有 2–8 个结果。用户不提交限价单，而是选择一个结果并买入其 pool。你的 position 是该结果 pool 中的 internal claim。

如果你的结果获胜，你会取回获胜本金，并获得失败结果 pools 的按比例份额。如果市场无效或取消，你可以取回本金。

## 交易 Close vs. 结算 Time

Parimutuel V2 市场有两个独立时间戳：

- **交易 close time** — 停止买入 pools 的时间。
- **结算 time** — 管理员、AI 或 Pyth 结算使用的事件/reference 时间戳。

这让 STRIKE 可以支持需要在结果已知前停止 betting 的市场，例如体育赛事、选举或 price-range 市场。

## Flap 代币池

FLAP 代币池是由创建者发起、以所选 BEP20 代币抵押的 parimutuel 市场。创建者定义结果、timing 和结算 prompt；Strike 使用固定的 FLAP AI resolver，并通过官方哈希校验元数据决定 pool 是否显示在应用中。

当前公开流程针对可通过 Ave-supported data 解析的代币数据 prompts 优化，例如 price、liquidity、volume、FDV 或 market cap。
