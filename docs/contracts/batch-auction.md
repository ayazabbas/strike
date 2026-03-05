# BatchAuction.sol

Handles Frequent Batch Auction clearing and pro-rata settlement.

## `clearBatch(marketId)`

Permissionless. Callable by anyone.

### Algorithm

1. **Check interval:** `block.timestamp >= lastClearTime + batchInterval` (skip for first clear)
2. **Find clearing tick:** segment tree binary search for highest tick where cumBid >= cumAsk, with tick+1 correction for maximum matched volume
3. **Compute volumes:** cumulative bid/ask lots at clearing tick, matched = min(bid, ask)
4. **Store result:** write `BatchResult` and advance batch counter
5. **Empty batches:** still stored (clearingTick = 0, matchedLots = 0)

### BatchResult Struct
```solidity
struct BatchResult {
    uint256 marketId;
    uint256 batchId;
    uint256 clearingTick;   // 0 = no cross
    uint256 matchedLots;
    uint256 totalBidLots;
    uint256 totalAskLots;
    uint256 timestamp;
}
```

## `claimFills(orderId)`

Settlement for a single order after its batch is cleared.

### Settlement Flow

1. Verify batch is cleared and order participates (bid tick >= clearing, ask tick <= clearing)
2. Compute pro-rata fill: `filledLots = (orderLots * matchedLots) / totalSideLots`
3. Calculate collateral split: filled collateral → market pool, unfilled → returned to owner
4. Deduct taker fee (BPS-based), send to protocol fee collector
5. Mint the single outcome token the user wants via `mintSingle()`:
   - **Bidder** receives YES token
   - **Asker** receives NO token
6. Remove order from book, update segment tree

### Collateral Model (Option A: BNB-only)

Both sides lock BNB collateral. Asks do NOT lock outcome tokens.
- Bid collateral: `lots * LOT_SIZE * tick / 100`
- Ask collateral: `lots * LOT_SIZE * (100 - tick) / 100`
- Sum per matched lot = LOT_SIZE (fully collateralized)

## `pruneExpiredOrder(orderId)`

Permissionless cleanup of expired GoodTilBatch orders. Returns collateral to order owner.

## Events

```solidity
event BatchCleared(uint256 indexed marketId, uint256 indexed batchId, uint256 clearingTick, uint256 matchedLots);
event FillClaimed(uint256 indexed orderId, address indexed owner, uint256 filledLots, uint256 collateralReleased);
event OrderPruned(uint256 indexed orderId, address indexed pruner);
```
