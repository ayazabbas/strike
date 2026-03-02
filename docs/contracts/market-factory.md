# MarketFactory.sol

Singleton factory that deploys and manages prediction markets.

## `createMarket(priceId, duration, batchInterval)`

- Deploys an EIP-1167 minimal proxy clone of the OrderBook implementation
- Requires market creation bond (funds resolver bounty)
- Registers market in the factory's market registry
- Emits `MarketCreated` event

### Parameters

| Param | Description | Constraints |
|-------|-------------|-------------|
| `priceId` | Pyth price feed ID | Must be whitelisted |
| `duration` | Market duration in seconds | 60s – 7 days |
| `batchInterval` | Batch clearing interval | ≥ 1 block time |

## Market Registry

- `getMarkets(offset, limit)` — paginated list of all markets
- `getActiveMarkets()` — markets in `Open` state
- `getMarketCount()` — total markets created

## Admin Functions

| Function | Access | Description |
|----------|--------|-------------|
| `pause()` / `unpause()` | Owner | Emergency pause on market creation |
| `setDefaultParams()` | Owner | Update default duration, batch interval, min lot size |
| `setFeeCollector()` | Owner | Update protocol fee collector address |
| `whitelistFeed()` | Owner | Add/remove allowed Pyth price feed IDs |

## Access Control

Initially admin-only market creation, with a path to permissionless creation once the protocol is battle-tested.
