# OrderBook.sol

Central limit order book for the Strike binary-outcome protocol. Single deployed contract manages all markets.

## Storage

- **Markets:** `mapping(uint256 => Market)` — market ID to market descriptor
- **Orders:** `mapping(uint256 => Order)` — order ID to order struct
- **Segment trees:** one per side per market (bid/ask), tracking aggregate volume at each tick

### Order Struct
```solidity
struct Order {
    uint256 id;
    uint256 marketId;
    address owner;
    Side side;           // Bid or Ask
    OrderType orderType; // GoodTilCancel or GoodTilBatch
    uint256 tick;        // 1-99
    uint256 lots;        // remaining lots (each = LOT_SIZE wei)
    uint256 batchId;     // batch when placed
    uint256 timestamp;
}
```

## Key Functions

### `placeOrder(marketId, side, orderType, tick, lots)`
- Validates: tick in [1,99], lots > 0, lots >= minLots, market active and not halted
- **Trading halt:** rejects if `block.timestamp + batchInterval >= expiryTime`
- Locks collateral in Vault:
  - **Bid:** `lots * LOT_SIZE * tick / 100`
  - **Ask:** `lots * LOT_SIZE * (100 - tick) / 100`
- Updates segment tree aggregate at tick

### `cancelOrder(orderId)`
- Only callable by order owner
- Unlocks collateral, updates segment tree
- Available while market is active

### `registerMarket(minLots, batchInterval, expiryTime)`
- OPERATOR_ROLE only (MarketFactory)
- Creates new market with given parameters

## Access Control

- **OPERATOR_ROLE:** BatchAuction (for `reduceOrderLots`, `updateTreeVolume`, `advanceBatch`) and MarketFactory (for `registerMarket`, `deactivateMarket`)
