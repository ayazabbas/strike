# OrderBook.sol

Central limit order book for Strike binary-outcome markets. A single deployed contract manages all CLOB markets.

## Storage

- **Markets:** `mapping(uint256 => Market)` — market ID to market descriptor.
- **Orders:** `mapping(uint256 => Order)` — order ID to order struct.
- **Segment trees:** two trees per market: bid-side liquidity and ask-side liquidity. `SellNo` maps into bid-side liquidity; `SellYes` maps into ask-side liquidity.

### Order Struct

```solidity
struct Order {
    address owner;
    Side side;
    OrderType orderType;
    uint8 tick;
    uint64 lots;
    uint64 id;
    uint32 marketId;
    uint32 batchId;
    uint40 timestamp;
    uint16 feeBps;
}
```

The struct is packed into two storage slots. `feeBps` stores the fee rate at placement so refunds and settlement use the correct locked-fee basis.

## Key Functions

### `placeOrder(marketId, side, orderType, tick, lots)`

- Validates: tick in `[1,99]`, lots >= market minimum, market active, market not halted, and `block.timestamp < expiryTime`.
- **Side enum:** `Bid` (0), `Ask` (1), `SellYes` (2), `SellNo` (3).
- Locks collateral in Vault (Bid/Ask) or custodies outcome positions (SellYes/SellNo):
  - **Bid:** `lots * LOT_SIZE * tick / 100` USDT plus fee.
  - **Ask:** `lots * LOT_SIZE * (100 - tick) / 100` USDT plus fee.
  - **SellYes:** locks YES positions.
  - **SellNo:** locks NO positions.
- Updates the relevant side's aggregate liquidity tree unless the order is parked as resting.

> **Internal positions:** For markets with `useInternalPositions = true` (current 5-minute markets), SellYes and SellNo work with internal position balances instead of ERC-1155 token transfers.

### `placeOrders(marketId, OrderParam[])`

- Batch order placement — places multiple orders in a single transaction.
- Uses one Vault deposit for total collateral across all orders.
- Each `OrderParam` specifies `(side, orderType, tick, lots)`.
- Returns placed order IDs.

### `replaceOrders(marketId, cancelOrderIds[], OrderParam[])`

- Atomic cancel-and-place — cancels existing orders and places new ones in one transaction.
- Nets collateral so only the difference is deposited or refunded.
- Useful for repositioning orders without separate cancel + place transactions.

### `amendOrders(marketId, AmendOrderParam[])`

Updates tick and/or lots for existing user orders in place, with collateral netting and resting-order state updated as needed.

### `cancelOrder(orderId)` / `cancelOrders(orderIds[])`

- Only callable by the order owner.
- Unlocks collateral or positions.
- Updates aggregate liquidity or resting-order state.
- Available while the market is active.

### `registerMarket(minLots, batchInterval, expiryTime, useInternalPositions)`

- `OPERATOR_ROLE` only, normally called by `MarketFactory`.
- Creates a new CLOB market with the given parameters.

## Anti-Spam: Per-User Order Cap

Each user is limited to **MAX_USER_ORDERS = 20** active orders per market. The `activeOrderCount[user][marketId]` mapping is incremented on placement and decremented on cancellation or settlement. The cap is enforced in `placeOrder`, `placeOrders`, and `replaceOrders`.

## Resting Orders

Orders placed more than **PROXIMITY_THRESHOLD = 20 ticks** from the last clearing tick are parked in a resting list rather than inserted into the segment tree.

| Storage / Function | Description |
|--------------------|-------------|
| `restingOrderIds[marketId]` | Array of resting order IDs for each market |
| `isResting[orderId]` | Whether an order is currently in the resting list |
| `isTickFar(marketId, tick)` | Returns true if `tick` is more than `PROXIMITY_THRESHOLD` from the last clearing tick |
| `pullRestingOrders(marketId)` | Moves in-range resting orders back into the segment tree, bounded by `MAX_RESTING_PULL` and `MAX_RESTING_SCAN` |

Resting orders still lock collateral or positions and can be cancelled normally. `OrderResting` is emitted instead of `OrderPlaced`.

## Access Control

- **OPERATOR_ROLE:** used by `BatchAuction` and `MarketFactory` for market lifecycle, batch advancement, clearing-tick updates, and resting-order pull-in.
- **DEFAULT_ADMIN_ROLE:** deployment/admin controls such as role management and next-ID recovery helpers.

## Events

```solidity
event MarketRegistered(uint256 indexed marketId, uint256 minLots);
event MarketHalted(uint256 indexed marketId);
event MarketResumed(uint256 indexed marketId);
event MarketDeactivated(uint256 indexed marketId);
event OrderPlaced(uint256 indexed orderId, uint256 indexed marketId, address indexed owner, Side side, uint256 tick, uint256 lots, uint256 batchId);
event OrderResting(uint256 indexed orderId, uint256 indexed marketId, address indexed owner);
event OrderCancelled(uint256 indexed orderId, uint256 indexed marketId, address indexed owner);
event OrderAmended(uint256 indexed orderId, uint256 indexed marketId, address indexed owner, uint256 oldTick, uint256 newTick, uint256 oldLots, uint256 newLots, uint256 oldFeeBps, uint256 newFeeBps, uint256 oldBatchId, uint256 newBatchId, bool wasResting, bool isResting);
```
