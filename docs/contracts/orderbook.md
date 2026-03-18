# OrderBook.sol

Central limit order book for the Strike binary-outcome protocol. Single deployed contract manages all markets.

## Storage

- **Markets:** `mapping(uint256 => Market)` — market ID to market descriptor
- **Orders:** `mapping(uint256 => Order)` — order ID to order struct
- **Segment trees:** one per side per market (bid/ask/sellYes/sellNo), tracking aggregate volume at each tick

### Order Struct
```solidity
struct Order {
    // --- Slot 1 (31 bytes) ---
    address owner;       // 20 bytes — order placer
    Side side;           // 1 byte  — Bid, Ask, SellYes, or SellNo
    OrderType orderType; // 1 byte  — GTC or GTB
    uint8 tick;          // 1 byte  — price tick 1-99 (price = tick/100)
    uint64 lots;         // 8 bytes — remaining lots (each lot = LOT_SIZE = 1e18 = 1 USDT)
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
- **Side enum:** `Bid` (0), `Ask` (1), `SellYes` (2), `SellNo` (3)
- Locks collateral in Vault (Bid/Ask) or custodies outcome tokens (SellYes/SellNo):
  - **Bid:** `lots * LOT_SIZE * tick / 100` USDT
  - **Ask:** `lots * LOT_SIZE * (100 - tick) / 100` USDT
  - **SellYes:** transfers `lots` YES tokens to OrderBook (ERC-1155)
  - **SellNo:** transfers `lots` NO tokens to OrderBook (ERC-1155)
- Updates segment tree aggregate at tick

### `placeOrders(marketId, OrderParam[])`
- Batch order placement — places multiple orders in a single transaction
- Single Vault deposit for total collateral across all orders (saves gas vs individual `placeOrder` calls)
- Each `OrderParam` specifies `(side, orderType, tick, lots)`
- Returns array of order IDs

### `replaceOrders(marketId, cancelOrderIds[], OrderParam[])`
- Atomic cancel-and-place — cancels existing orders and places new ones in a single transaction
- Net settlement: only the difference in collateral is deposited or refunded
- Useful for repositioning orders without separate cancel + place transactions

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
- Only callable by order owner
- Unlocks collateral (Bid/Ask) or returns custodied tokens (SellYes/SellNo)
- Updates segment tree
- Available while market is active

### `registerMarket(minLots, batchInterval, expiryTime)`
- OPERATOR_ROLE only (MarketFactory)
- Creates new market with given parameters

## Access Control

- **OPERATOR_ROLE:** BatchAuction (for `reduceOrderLots`, `updateTreeVolume`, `advanceBatch`) and MarketFactory (for `registerMarket`, `deactivateMarket`)

## Events

```solidity
event MarketRegistered(uint256 indexed marketId, uint256 minLots);
event MarketHalted(uint256 indexed marketId);
event MarketResumed(uint256 indexed marketId);
event MarketDeactivated(uint256 indexed marketId);
event OrderPlaced(uint256 indexed orderId, uint256 indexed marketId, address indexed owner, Side side, uint256 tick, uint256 lots, uint256 batchId);
event OrderCancelled(uint256 indexed orderId, address indexed owner);
```
