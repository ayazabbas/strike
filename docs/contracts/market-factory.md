# MarketFactory.sol

Singleton factory that creates and manages CLOB prediction markets.

## Market Creation

### `createMarket(priceId, strikePrice, expiryTime, batchInterval, minLots)`

Creates a Pyth-resolved binary market and registers it in `OrderBook`.

### `createMarketWithPositions(priceId, strikePrice, expiryTime, batchInterval, minLots)`

Creates a Pyth-resolved market that uses internal position accounting instead of ERC-1155 outcome-token transfers. Current 5-minute markets use this path.

### `createAIMarket(prompt, modelId, expiryTime, minLots)`

Creates an AI-resolved orderbook market and deposits the AI resolver fee. This is an admin/protocol integration surface; public creator flows should use Flap Token Pools.

All creation functions require `MARKET_CREATOR_ROLE` and emit `MarketCreated`.

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

## State Machine

```
Open → Closed → Resolving → Resolved
                               ↓
Open → Closed ─────────────→ Cancelled
```

## Transitions

| From | To | Trigger | Condition |
|------|----|---------|-----------|
| Open | Closed | `closeMarket()` | `block.timestamp >= expiryTime` |
| Closed | Resolving | `setResolving()` | `ADMIN_ROLE` |
| Resolving | Resolved | `setResolved()` | `ADMIN_ROLE` |
| Open/Closed | Cancelled | `setCancelled()` / fallback flow | `ADMIN_ROLE` or configured cancellation path |

## Registry

- `getActiveMarketCount()` — number of markets in Open state.
- `getClosedMarketCount()` — number of closed markets.
- `getResolvedMarketCount()` — number of resolved markets.

## Admin Functions

| Function | Access | Description |
|----------|--------|-------------|
| `pauseFactory()` | `ADMIN_ROLE` | Emergency pause on market creation |
| `setDefaultParams(batchInterval, minLots, feeBps)` | `ADMIN_ROLE` | Update default market parameters |
| `setAIResolver(resolver)` | `ADMIN_ROLE` | Update AI resolver address |
| `setNextFactoryMarketId(nextId)` | `DEFAULT_ADMIN_ROLE` | Recovery helper for redeployments |

## Access Control

- **DEFAULT_ADMIN_ROLE:** role management and recovery helpers.
- **ADMIN_ROLE:** lifecycle updates such as resolving, cancellation, pause, default params, and AI resolver.
- **MARKET_CREATOR_ROLE:** market creation.
- `closeMarket()` is permissionless once expiry has passed.

## Events

```solidity
event MarketCreated(uint256 indexed factoryMarketId, uint256 indexed orderBookMarketId, bytes32 priceId, int64 strikePrice, uint256 expiryTime, address indexed creator);
event MarketClosed(uint256 indexed factoryMarketId);
event MarketStateChanged(uint256 indexed factoryMarketId, MarketState newState);
event FactoryPaused(bool paused);
event DefaultParamsUpdated(uint256 batchInterval, uint128 minLots);
```
