# OrderBook.sol

Central limit order book for the Strike binary-outcome protocol. Single deployed contract manages all markets.

## Storage

- **Markets:** `mapping(uint256 => Market)` — market ID to market descriptor
- **Orders:** `mapping(uint256 => Order)` — order ID to order struct
- **Segment trees:** one per side per market (bid/ask), tracking aggregate volume at each tick

### Order Struct
```solidity
struct Order {
    // --- Slot 1 (31 bytes) ---
    address owner;       // 20 bytes — order placer
    Side side;           // 1 byte  — Bid or Ask
    OrderType orderType; // 1 byte  — GTC or GTB
    uint8 tick;          // 1 byte  — price tick 1-99 (price = tick/100)
    uint64 lots;         // 8 bytes — remaining lots (each lot = 1e15 wei)
    // --- Slot 2 (21 bytes) ---
    uint64 id;           // 8 bytes — unique order ID
    uint32 marketId;     // 4 bytes — market this order belongs to
    uint32 batchId;      // 4 bytes — batch ID when order was placed
    uint40 timestamp;    // 5 bytes — block.timestamp when placed
}
```

The struct is tightly packed into 2 storage slots for gas efficiency.

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
