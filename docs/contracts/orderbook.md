# OrderBook.sol

Per-market orderbook contract deployed as an EIP-1167 minimal proxy clone.

## Storage

- **Orders:** `mapping(uint256 => Order)` — order ID to order struct
- **Segment trees:** one per side (bid/ask), tracking aggregate volume at each tick
- **Batch results:** `mapping(uint256 => BatchResult)` — batch ID to clearing result

### Order Struct
```solidity
struct Order {
    address owner;
    Side side;        // Bid or Ask
    uint8 tick;       // 1-99
    uint256 amount;   // Total size
    uint256 remaining; // Unfilled size
    uint256 batchId;  // Batch when placed
    uint256 expiry;   // Auto-expire timestamp
    OrderType orderType; // Limit, PostOnly, IOC, BatchOnly
    bool cancelled;
}
```

## Key Functions

### `placeOrder(side, tick, amount, orderType, expiry)`
- Validates: tick in range, amount ≥ min lot size, expiry ≤ market close, market is Open
- **Trading halt:** rejects if `block.timestamp + batchInterval >= expiryTime`
- Locks collateral (bids) or outcome tokens (asks) in Vault
- Deposits order bond
- Updates segment tree aggregate at tick
- Post-only: reverts if order would cross the book

### `cancelOrder(orderId)`
- Only callable by order owner
- Unlocks collateral/tokens, refunds order bond
- Updates segment tree aggregate
- Available in Open and Closed states

### `claimFills(orderId[])`
- Batch claim for gas efficiency
- Computes fill amount per order based on stored `BatchResult`
- Transfers outcome tokens or collateral via Vault
- Deducts taker fee / applies maker rebate
- Marks order as claimed for that batch

### `pruneExpiredOrders(orderId[])`
- Permissionless — anyone can call
- Removes expired orders, returns collateral to owner
- Pays pruner bounty from order bond
- Updates segment tree aggregates
