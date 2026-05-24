# MarketFactory.sol

用于创建和管理预测市场的 singleton factory。

## `createMarket(priceId, duration, batchInterval, minLots)`

- 通过 `registerMarket()` 在订单簿中注册新市场。
- 需要 MARKET_CREATOR_ROLE。
- 存储市场 metadata，并跟踪市场生命周期。
- 触发 `MarketCreated` 事件。

### 参数

| Param | Description | 默认 |
|-------|-------------|---------|
| `priceId` | Pyth price feed ID (bytes32) | 必需 |
| `duration` | 市场持续时间，单位为 seconds | 必需 |
| `batchInterval` | Batch 清算间隔（0 = 默认 60 秒） | 60 秒 |
| `minLots` | 最小订单规模（0 = 默认 1） | 1 |

## State Machine

```
Open → Closed → Resolving → Resolved
                               ↓
Open → Closed ─────────────→ Cancelled
```

### Transitions

| 从 | 到 | Trigger | Condition |
|------|----|---------|-----------|
| Open | Closed | `closeMarket()` | `block.timestamp >= expiryTime` |
| Closed | Resolving | `setResolving()` | ADMIN_ROLE (PythResolver) |
| Resolving | Resolved | `setResolved()` | ADMIN_ROLE (PythResolver) |
| Open/Closed | Cancelled | `cancelMarket()` | expiry 之后 24h，仍未结算 |

## 市场 Registry

- `getActiveMarketCount()` — 处于 Open 状态的市场数量。
- `getClosedMarketCount()` — closed 市场数量。
- `getResolvedMarketCount()` — resolved 市场数量。

## Admin 函数

| Function | Access | Description |
|----------|--------|-------------|
| `pauseFactory()` | ADMIN_ROLE | 紧急暂停市场创建 |
| `setDefaultParams()` | ADMIN_ROLE | 更新默认批次间隔及 min lots |
| `setCreationBond()` | ADMIN_ROLE | 更新所需 creation bond |
| `setFeeCollector()` | ADMIN_ROLE | 更新协议费用收集器地址 |

## 访问控制

- **ADMIN_ROLE:** 授予 PythResolver（用于 `setResolving`、`setResolved`、`payResolverBounty`）。
- **DEFAULT_ADMIN_ROLE:** 协议管理员（暂停、参数更新）。
- `closeMarket()` 和 `cancelMarket()` 无需许可。
- 市场创建需要 MARKET_CREATOR_ROLE。

## 事件

```solidity
event MarketCreated(uint256 indexed factoryMarketId, uint256 indexed orderBookMarketId, bytes32 priceId, int64 strikePrice, uint256 expiryTime, address indexed creator);
event MarketClosed(uint256 indexed factoryMarketId);
event MarketStateChanged(uint256 indexed factoryMarketId, MarketState newState);
event FactoryPaused(bool paused);
event DefaultParamsUpdated(uint256 batchInterval, uint128 minLots);
event CreationBondUpdated(uint256 newBond);
event FeeCollectorUpdated(address indexed collector);
event ResolverBountyPaid(uint256 indexed factoryMarketId, address indexed resolver, uint256 amount);
```
