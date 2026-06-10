# MarketFactory.sol

用于创建和管理 CLOB 预测市场的单例 factory。

## 市场创建

### `createMarket(priceId, strikePrice, expiryTime, batchInterval, minLots)`

创建 Pyth 结算的二元市场，并在 `OrderBook` 中注册。

### `createMarketWithPositions(priceId, strikePrice, expiryTime, batchInterval, minLots)`

创建使用内部仓位记账的 Pyth 结算市场，而不是通过 ERC-1155 结果代币转移。当前 5 分钟市场使用这一路径。

### `createAIMarket(prompt, modelId, expiryTime, minLots)`

创建 AI 结算订单簿市场，并存入 AI resolver fee。这是管理员/协议集成接口；公开 creator flow 应使用 Flap Token Pools。

所有创建函数都需要 `MARKET_CREATOR_ROLE`，并会发出 `MarketCreated`。

## `MarketMeta`

```solidity
struct MarketMeta {
    bytes32 priceId;
    int64 strikePrice;
    uint256 expiryTime;
    address creator;
    MarketState state;
    bool outcomeYes;
    int64 settlementPrice;
    uint256 orderBookMarketId;
    bool useInternalPositions;
    bool isAIMarket;
}
```

## 状态机

```
Open → Closed → Resolving → Resolved
                               ↓
Open → Closed ─────────────→ Cancelled
```

## 状态转换

| From | To | Trigger | Condition |
|------|----|---------|-----------|
| Open | Closed | `closeMarket()` | `block.timestamp >= expiryTime` |
| Closed | Resolving | `setResolving()` | `ADMIN_ROLE` |
| Resolving | Resolved | `setResolved()` | `ADMIN_ROLE` |
| Open/Closed | Cancelled | `setCancelled()` / fallback flow | `ADMIN_ROLE` 或配置的 cancellation path |

## Registry

- `getActiveMarketCount()` — Open 状态市场数量。
- `getClosedMarketCount()` — Closed 状态市场数量。
- `getResolvedMarketCount()` — Resolved 状态市场数量。

## 管理函数

| Function | Access | Description |
|----------|--------|-------------|
| `pauseFactory()` | `ADMIN_ROLE` | 紧急暂停市场创建 |
| `setDefaultParams(batchInterval, minLots, feeBps)` | `ADMIN_ROLE` | 更新默认市场参数 |
| `setAIResolver(resolver)` | `ADMIN_ROLE` | 更新 AI resolver 地址 |
| `setNextFactoryMarketId(nextId)` | `DEFAULT_ADMIN_ROLE` | redeployment/recovery helper |

## 访问控制

- **DEFAULT_ADMIN_ROLE:** role 管理和 recovery helpers。
- **ADMIN_ROLE:** resolving、cancellation、pause、默认参数和 AI resolver 等生命周期/管理操作。
- **MARKET_CREATOR_ROLE:** 市场创建。
- `closeMarket()` 在 expiry 后可由任何人调用。

## Events

```solidity
event MarketCreated(uint256 indexed factoryMarketId, uint256 indexed orderBookMarketId, bytes32 priceId, int64 strikePrice, uint256 expiryTime, address indexed creator);
event MarketClosed(uint256 indexed factoryMarketId);
event MarketStateChanged(uint256 indexed factoryMarketId, MarketState newState);
event FactoryPaused(bool paused);
event DefaultParamsUpdated(uint256 batchInterval, uint128 minLots);
```
