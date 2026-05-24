# 订单簿.sol

STRIKE 二元结果协议的 central limit order book。单个部署合约管理所有市场。

## 存储

- **市场:** `mapping(uint256 => Market)` — 市场 ID 到市场描述信息。
- **订单:** `mapping(uint256 => Order)` — 订单 ID 到订单 struct。
- **Segment trees:** 每个市场、每个 side（bid/ask/sellYes/sellNo）各有一棵树，用于跟踪每个 tick 的聚合成交量。

### 订单 Struct
```solidity
struct Order {
    // --- Slot 1 (31 bytes) ---
    address owner;       // 20 bytes — order placer
    Side side;           // 1 byte  — Bid, Ask, SellYes, or SellNo
    OrderType orderType; // 1 byte  — GTC or GTB
    uint8 tick;          // 1 byte  — price tick 1-99 (price = tick/100)
    uint64 lots;         // 8 bytes — remaining lots (each lot = LOT_SIZE = 1e16 = $0.01)
    // --- Slot 2 (21 bytes) ---
    uint64 id;           // 8 bytes — unique order ID
    uint32 marketId;     // 4 bytes — market this order belongs to
    uint32 batchId;      // 4 bytes — batch ID when order was placed
    uint40 timestamp;    // 5 bytes — block.timestamp when placed
}
```

该 struct 紧凑打包为 2 个 storage slot，以提升 Gas 效率。

## 关键函数

### `placeOrder(marketId, side, orderType, tick, lots)`
- 校验: tick 在 [1,99] 内，lots > 0，lots >= minLots，市场处于活跃且未暂停状态。
- **交易停止:** 如果 `block.timestamp + batchInterval >= expiryTime`，则拒绝下单。
- **Side enum:** `Bid` (0), `Ask` (1), `SellYes` (2), `SellNo` (3)。
- 在金库中锁定抵押资产（Bid/Ask），或托管结果代币（SellYes/SellNo）：
 - **Bid:** `lots * LOT_SIZE * tick / 100` USDT
 - **Ask:** `lots * LOT_SIZE * (100 - tick) / 100` USDT
 - **SellYes:** 将 `lots` YES 代币转入订单簿（ERC-1155，用于 non-internal 市场）。
 - **SellNo:** 将 `lots` NO 代币转入订单簿（ERC-1155，用于 non-internal 市场）。
- 按 tick 更新线段树聚合量。

> **Internal positions:** 对于使用 `useInternalPositions = true` 的市场（当前 5 分钟市场），SellYes 及 SellNo 使用 internal position balances，而非 ERC-1155 代币转账。

### `placeOrders(marketId, OrderParam[])`
- 批量下单，即在单笔交易中提交多个订单。
- 对所有订单的总抵押资产执行一次金库 deposit，相比逐笔调用 `placeOrder` 更节省 Gas。
- 每个 `OrderParam` 指定 `(side, orderType, tick, lots)`。
- 返回订单 ID 数组。

### `replaceOrders(marketId, cancelOrderIds[], OrderParam[])`
- 原子化取消并下单，即在单笔交易中取消现有订单并提交新订单。
- 净额结算: 仅对抵押资产差额执行 deposit 或退款。
- 适用于重新调整订单位置，无需分别发送取消交易和下单交易。

### OrderParam Struct
```solidity
struct OrderParam {
    Side side;           // Bid, Ask, SellYes, or SellNo
    OrderType orderType; // GoodTilBatch or GoodTilCancel
    uint8 tick;          // price tick 1-99
    uint64 lots;         // number of lots
}
```

### `cancelOrder(orderId)`
- 仅订单所有者可以调用。
- 解锁抵押资产（Bid/Ask），或返还已托管代币（SellYes/SellNo）。
- 更新线段树。
- 市场活跃期间可用。

### `registerMarket(minLots, batchInterval, expiryTime)`
- 仅 OPERATOR_ROLE 可调用（MarketFactory）。
- 使用给定参数创建新市场。

## Anti-Spam: 每用户订单上限

每个用户在每个市场最多只能拥有 **MAX_USER_ORDERS = 20** 个活跃订单。`activeOrderCount[marketId][user]` mapping 会在下单时递增，并在取消或结算时递减。该限制在 `placeOrder`、`placeOrders` 和 `replaceOrders` 中强制执行。

## 休眠订单（价格接近度过滤）

距离上次清算 tick 超过 **PROXIMITY_THRESHOLD = 20 ticks** 的订单会进入休眠列表，而不是插入线段树。

| 存储 / Function | Description |
|--------------------|-------------|
| `restingOrderIds[marketId]` | 每个市场的休眠订单 ID 数组 |
| `isResting[orderId]` | 订单当前是否在休眠列表中 |
| `isTickFar(marketId, tick)` | 如果 `tick` 与上次清算 tick 的距离超过 PROXIMITY_THRESHOLD，则返回 true |
| `pullRestingOrders(marketId)` | 将范围内的休眠订单移回线段树（最多拉取 **MAX_RESTING_PULL = 200** 个，最多扫描 **MAX_RESTING_SCAN = 400** 个） |

休眠订单仍然锁定抵押资产或代币，并且可以正常取消。系统会触发 `OrderResting` 事件，而不是 `OrderPlaced`。

## 访问控制

- **OPERATOR_ROLE:** 授予 BatchAuction（用于 `reduceOrderLots`、`updateTreeVolume`、`advanceBatch`、`pullRestingOrders`）及 MarketFactory（用于 `registerMarket`、`deactivateMarket`）。

## 事件

```solidity
event MarketRegistered(uint256 indexed marketId, uint256 minLots);
event MarketHalted(uint256 indexed marketId);
event MarketResumed(uint256 indexed marketId);
event MarketDeactivated(uint256 indexed marketId);
event OrderPlaced(uint256 indexed orderId, uint256 indexed marketId, address indexed owner, Side side, uint256 tick, uint256 lots, uint256 batchId);
event OrderResting(uint256 indexed orderId, uint256 indexed marketId, address indexed owner, Side side, uint256 tick, uint256 lots);
event OrderCancelled(uint256 indexed orderId, address indexed owner);
```
