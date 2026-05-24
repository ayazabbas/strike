# MEV 缓解

## 问题

在连续订单簿中，MEV bots 会利用时间优先级进行 front-running、sandwiching，以及抢先取消过时报价。这会从交易者手中抽取价值，并损害市场公平性。

## FBA 如何缓解

Frequency Batch Auctions 会消除同一批次内的时间优先级：

- **同一批次内无法 front-run** - 同一 batch 中的所有订单都会被同等处理
- **统一清算价格** - 不会因为订单成交顺序产生连续价格冲击
- **Maker 保护** - maker 拥有完整的批次间隔，可在下一次清算前取消过时报价

## 剩余 MEV 向量

FBA 并不能消除所有 MEV。公开链上下单仍然会暴露交易意图：

### 批次边界策略

成熟参与者可以观察 mempool 中的待处理订单，并于 batch 截止前提交订单。与逐区块清算相比，多区块 batch（默认 60 秒）可以降低这种优势。

### 取消竞争

Maker 可能会在批次清算前抢先取消过时报价。批次间隔给 maker 留出了反应时间，也是抵御 front-running 的主要保护机制。

### 结算观察

临近到期时，交易者可能发现 Pyth price 变化，并尝试抢跑最终 batch。**缓解措施：** 当 `timeRemaining < batchInterval` 时停止交易，避免于对结算敏感的时间段内继续交易。

## BNB Chain MEV 基础设施

BNB Chain 提供生态层面的 MEV 缓解工具：

| Tool | Description |
|------|-------------|
| **BEP-322 Builder API** | 用于私有交易传递的 builder/validator 分离机制 |
| **NodeReal Bundle API** | 私有原子化交易包（不会向 P2P 网络传播） |
| **Chainstack MEV Protection** | 把交易路由给 builders，绕过公开 mempool |

## 可选私有提交

Strike 支持可选的私有提交路径：

- **默认：** 公开链上提交（最简单、可组合性最高）
- **高级：** 通过受 MEV 保护的 RPC endpoints 路由订单以获得隐私保护
- **前端开关：** Web 界面中的 "Submit privately" 选项
- **平滑降级：** 无论提交方式如何，协议行为都保持一致

这是基础设施层面的功能，不是协议层面的保证。它依赖私有交易 relays 的可用性及其信任假设。
