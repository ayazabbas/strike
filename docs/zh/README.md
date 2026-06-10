# Strike 简介

**Strike** 是部署于 BNB Chain 的完全链上预测市场协议，现已通过 [strike.fun](https://strike.fun) 上线。Strike 当前支持多类市场：用于主动二元交易的 **FBA 订单簿市场**、用于简单多结果预测的**标准同注分彩池市场**、由创建者发起并使用 BEP20 抵押资产的 **[Flap Token Pools](getting-started/flap-token-pools.md)**，以及面向活动的 USDT 预测池 **[世界杯市场](getting-started/world-cup.md)**。

订单簿市场使用 **Frequent Batch Auction (FBA) CLOB**。订单会在周期性批次中收集，并按统一价格清算。这为交易者提供真实的价格发现、限价单和公平执行，同时避免连续订单簿常见的 MEV 问题。

同注分彩池市场让用户可以直接在资金池界面中支持 2–8 个结果之一。用户不需要管理订单簿：买入某个结果池后，市场结算时获胜方按比例瓜分失败方资金池。[Flap Token Pools](getting-started/flap-token-pools.md) 将这一资金池模型扩展到由创建者发起的代币市场，支持外部 BEP20 抵押资产与 FLAP AI 结算。[世界杯市场](getting-started/world-cup.md) 则提供活动型 USDT 体验，支持钱包 USDT、奖励 Credit、早鸟预测激励，以及在配置后显示 KOL 信号图标。

根据市场类型和配置，市场可以通过 **Pyth 网络** 价格源、**Flap AI Oracle** 或管理员兜底路径完成结算。

## 核心属性

- **已上线的市场引擎**：FBA 订单簿市场、标准同注分彩池与 [Flap Token Pools](getting-started/flap-token-pools.md) 已部署于 BNB Chain。
- **链上订单簿**：所有下单、撮合和结算都通过 BNB Chain 智能合约完成。
- **批量拍卖清算**：订单簿市场在每个批次内按单一统一清算价撮合，超额一侧按比例成交。
- **同注分彩池**：支持 2–8 个结果的市场，获胜方取回本金并按比例获得失败方资金池份额。
- **拆分时间窗口**：同注分市场支持独立的 `tradingCloseTime` 与 `resolutionTime`，因此下注可在事件结算前关闭。
- **官方平台代币**：`$STRIKE` 是 Strike 协议的官方平台代币。
- **多种抵押资产**：订单簿市场使用 USDT；标准资金池使用 USDT 或 `$STRIKE`；Flap Token Pools 可使用创建者选择的 BEP20 抵押资产。
- **Pyth + FLAP AI 结算**：支持确定性的价格源市场、管理员结算资金池与 AI 结算资金池，并可按配置启用挑战或兜底路径。
- **原子化订单簿结算**：`clearBatch(marketId)` 会在单笔交易中清算一个订单簿批次并内联结算所有订单。
- **统一费用**：订单簿交易收取 20 bps 的成交抵押资产费用；资金池市场使用配置的协议费用。

## 架构速览

```
Orderbook traders ──→ OrderBook ──→ BatchAuction (atomic clear + settle)
                         │                       │
                    Vault (USDT escrow)    Positions (internal)
                         │                       │
                  MarketFactory ◄── PythResolver / AIResolver ──→ Redemption

Pool traders ─────→ ParimutuelPoolManager ──→ ParimutuelVault
                         │                           │
                  ParimutuelFactory ◄── AI/Pyth/Admin resolution ──→ ParimutuelRedemption

Flap pool creators/traders ─→ NativeTokenPoolManager ─→ NativeTokenPoolVault
                         │                                  │
          NativeTokenParimutuelFactory ◄── NativeTokenPoolAIResolver ─→ NativeTokenPoolRedemption

Off-chain (non-authoritative):
  • Keepers (clear batches, close pools, resolve markets)
  • Indexer + API (orderbook snapshots, pool state, trade history, WebSocket)
  • Web Frontend (orderbook terminal + pool market interface)
```

## 链接

- **应用：** [strike.fun](https://strike.fun)
- **文档：** [docs.strike.fun](https://docs.strike.fun)
- **链：** BNB Chain (BSC)
- **预言机：** [Pyth 网络](https://pyth.network/)
