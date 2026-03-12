# MarketFactory.sol

Singleton factory that creates and manages prediction markets.

## `createMarket(priceId, duration, batchInterval, minLots)`

- Registers a new market in OrderBook via `registerMarket()`
- Requires MARKET_CREATOR_ROLE
- Stores MarketMeta with lifecycle tracking
- Emits `MarketCreated` event

### Parameters

| Param | Description | Default |
|-------|-------------|---------|
| `priceId` | Pyth price feed ID (bytes32) | required |
| `duration` | Market duration in seconds | required |
| `batchInterval` | Batch clearing interval (0 = use default 60s) | 60s |
| `minLots` | Minimum order size (0 = use default 1) | 1 |

## State Machine

```
Open → Closed → Resolving → Resolved
                               ↓
Open → Closed ─────────────→ Cancelled
```

### Transitions

| From | To | Trigger | Condition |
|------|----|---------|-----------|
| Open | Closed | `closeMarket()` | `block.timestamp >= expiryTime` |
| Closed | Resolving | `setResolving()` | ADMIN_ROLE (PythResolver) |
| Resolving | Resolved | `setResolved()` | ADMIN_ROLE (PythResolver) |
| Open/Closed | Cancelled | `cancelMarket()` | 24h after expiry, no resolution |

## Market Registry

- `getActiveMarketCount()` — number of markets in Open state
- `getClosedMarketCount()` — number of closed markets
- `getResolvedMarketCount()` — number of resolved markets

## Admin Functions

| Function | Access | Description |
|----------|--------|-------------|
| `pauseFactory()` | ADMIN_ROLE | Emergency pause on market creation |
| `setDefaultParams()` | ADMIN_ROLE | Update default batch interval + min lots |
| `setCreationBond()` | ADMIN_ROLE | Update required creation bond |
| `setFeeCollector()` | ADMIN_ROLE | Update protocol fee collector address |

## Access Control

- **ADMIN_ROLE:** PythResolver (for `setResolving`, `setResolved`, `payResolverBounty`)
- **DEFAULT_ADMIN_ROLE:** protocol admin (pause, parameter updates)
- `closeMarket()` and `cancelMarket()` are permissionless
- Market creation requires MARKET_CREATOR_ROLE

## Events

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
