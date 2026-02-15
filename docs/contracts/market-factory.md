# MarketFactory.sol

The factory contract that deploys and manages prediction markets using the EIP-1167 minimal proxy pattern.

## Key Functions

### `createMarket()`

Deploy a new prediction market.

```solidity
function createMarket(
    bytes32 priceId,
    uint256 duration,
    bytes[] calldata pythUpdateData
) external payable returns (address market)
```

- **Access:** Keeper or owner only
- **Duration:** Must be between 60 seconds and 7 days
- Deploys an EIP-1167 clone of the Market implementation
- Calls `initialize()` on the new clone
- Registers the market in the factory's registry
- Emits `MarketCreated` event

### `getMarkets()`

List deployed markets with pagination.

```solidity
function getMarkets(uint256 offset, uint256 limit)
    external view returns (address[] memory markets)
```

### `getMarketCount()`

Total number of markets created.

```solidity
function getMarketCount() external view returns (uint256)
```

### Admin Functions

| Function | Description |
|----------|-------------|
| `setKeeper(address)` | Set the keeper address (can create/resolve markets) |
| `removeKeeper(address)` | Remove a keeper |
| `pause()` / `unpause()` | Emergency controls |
| `withdrawFees()` | Withdraw collected protocol fees |

## Registry

The factory maintains an ordered list of all deployed markets. This serves as the on-chain registry for market discovery.

```
markets[0] → 0x1a33...Bf99  (oldest)
markets[1] → 0xca5f...bf0f
markets[2] → 0x...           (newest)
```

## Events

| Event | When |
|-------|------|
| `MarketCreated(market, priceId, strikePrice, duration)` | New market deployed |
| `KeeperAdded(keeper)` | Keeper role granted |
| `KeeperRemoved(keeper)` | Keeper role revoked |
