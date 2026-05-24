# BatchAuction.sol

处理频繁批量拍卖清算，以及原子化的按比例结算。

## `clearBatch(marketId)`

无需许可，任何人都可以调用。它会在单笔交易中清算当前批次并原子化结算所有订单。合约会从 `batchOrderIds[marketId][batchId]` 内部读取订单 ID，除 `marketId` 外不需要其他参数。

### Algorithm

1. **校验市场:** 检查市场存在、处于活跃状态且未暂停。
2. **查找清算 tick:** 在线段树上执行二分搜索，找到满足 cumBid >= cumAsk 的最高 tick，并通过 tick+1 校正确保最大化 matched volume。
3. **计算成交量:** 计算清算 tick 处的累计 bid/ask lots，matched = min(bid, ask)。如果 matched = 0，则清算 tick 重置为 0（无交叉）。
4. **存储结果:** 写入包含 marketId、batchId、clearingTick、matchedLots、totalBidLots、totalAskLots 和时间戳的 `BatchResult`。
5. **推进批次:** 递增 `currentBatchId`，让新订单进入下一个批次。
6. **结算所有订单:** 遍历 `batchOrderIds[marketId][batchId]`，并对每个订单内联结算（按清算价格按比例成交、铸造代币、退回多余抵押资产）。
7. **空批次:** 仍会存储结果（清算 tick = 0，matchedLots = 0）。

### Batch 结果 Struct
```solidity
struct BatchResult {
    uint32  marketId;
    uint32  batchId;
    uint8   clearingTick;   // 0 = no cross
    uint64  matchedLots;
    uint64  totalBidLots;
    uint64  totalAskLots;
    uint40  timestamp;
}
```

### 内联结算流程

对 `batchOrderIds[marketId][batchId]` 中的每个订单：

**未参与成交的订单**（tick 未穿越清算价格）：
- **GoodTilBatch (GTB):** 从订单簿移除，并将全部抵押资产退回钱包。
- **GoodTilCancel (GTC):** 留在订单簿中，并通过 `pushBatchOrderId()` 滚入下一个批次。

**参与成交的订单**（按清算价格结算，而不是按订单 tick 结算）：
1. 计算按比例成交量: `filledLots = (orderLots * matchedLots) / totalSideLots`。
2. 按**清算 tick** 计算已成交抵押资产，而不是按订单的 limit tick 计算。
3. 多余退款 =（按订单 tick 锁定的抵押资产）-（按清算 tick 计算的成本）。
4. 扣除费用（总计 20 bps，50/50 分摊）: buy side 支付 `floor(fee/2)`，sell side 从 USDT payout 中支付 `ceil(fee/2)`。费用发送到协议费用收集器。
5. 通过 `mintSingle()` 铸造结果代币（或为 `useInternalPositions` 市场记入 internal position）：
 - **Bidder** 获得 YES 代币（或 YES position credit）。
 - **Asker** 获得 NO 代币（或 NO position credit）。
6. 从订单中扣减已成交 lots，并更新线段树。
7. **完全成交或 GTB:** 将未成交抵押资产和多余退款提取到钱包。
8. **部分成交 GTC:** 将剩余部分滚入下一个批次；如有多余退款，则提取到钱包。

### 抵押资产模型 (USDT)

双方都锁定 USDT 抵押资产（ERC-20）。用户必须先授权金库，然后才能下单。Ask 不锁定结果代币。
- Bid 抵押资产: `lots * LOT_SIZE * tick / 100`
- Ask 抵押资产: `lots * LOT_SIZE * (100 - tick) / 100`
- 每个 matched lot 两边合计为 LOT_SIZE (1e16 = $0.01)，因此完全抵押。

### 清算价格结算

所有成交都按**清算 tick** 结算，而不是按订单的 limit tick 结算。这意味着：
- 一笔 tick 70 的 bid 如果在清算 tick 55 成交，则每 lot 只支付 55%（不是 70%）。
- 多余部分（70% - 55% = 每 lot 15%）会退回 bidder。
- Ask 侧按对称逻辑处理。

### 分块结算

大批次可以跨多次 `clearBatch` 调用结算：

- **MAX_ORDERS_PER_BATCH = 1600**（从 v1.1 的 400 上调）。
- **SETTLE_CHUNK_SIZE = 400** — 每次 `clearBatch` 调用最多结算 400 个订单。
- 对某个批次的第一次调用会计算并存储清算 tick 与匹配手数，作为预计算成交结果。
- 后续调用复用预计算成交结果，并结算下一块订单。
- 在结算期间，零成交的 GTB 订单会通过 `_tryRollOrCancel` 清理。

### 休眠订单处理

每次 `clearBatch` 开始时，系统会调用 `pullRestingOrders`，在清算前把范围内的休眠订单移回线段树。结算后，如果 GTC 订单已远离新的清算价格，会通过 `_tryRollOrCancel` 滚入休眠列表，而不是继续留在活跃树中。

### 批次溢出

`MAX_ORDERS_PER_BATCH = 1600`。当当前 batch 达到 1600 个订单时，新订单会自动进入下一个批次。只有当前批次和下一个批次都已满时，下单才会失败。

## 事件

```solidity
event BatchCleared(uint256 indexed marketId, uint256 indexed batchId, uint256 clearingTick, uint256 matchedLots);
event OrderSettled(uint256 indexed orderId, address indexed owner, uint256 filledLots, uint256 collateralReleased);
```
