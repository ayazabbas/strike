# BatchAuction.sol

Handles Frequent Batch Auction clearing and atomic pro-rata settlement.

## `clearBatch(marketId)`

Permissionless. Callable by anyone. Clears the current batch and settles all orders atomically in a single transaction. The contract reads order IDs internally from `batchOrderIds[marketId][batchId]` — no parameters beyond `marketId` are needed.

### Algorithm

1. **Validate market:** check market exists, is active, not halted
2. **Find clearing tick:** segment tree binary search for highest tick where cumBid >= cumAsk, with tick+1 correction for maximum matched volume
3. **Compute volumes:** cumulative bid/ask lots at clearing tick, matched = min(bid, ask). If matched = 0, clearing tick reset to 0 (no cross)
4. **Store result:** write `BatchResult` with marketId, batchId, clearingTick, matchedLots, totalBidLots, totalAskLots, timestamp
5. **Advance batch:** increment `currentBatchId` so new orders go to the next batch
6. **Settle all orders:** loop through `batchOrderIds[marketId][batchId]` and settle each order inline (pro-rata fill at clearing price, mint tokens, return excess collateral)
7. **Empty batches:** still stored (clearingTick = 0, matchedLots = 0)

### BatchResult Struct
```solidity
struct BatchResult {
    uint32  marketId;
    uint32  batchId;
    uint8   clearingTick;   // 0 = no cross
    uint64  matchedLots;
    uint64  totalBidLots;
    uint64  totalAskLots;
    uint40  timestamp;
}
```

### Inline Settlement Flow

For each order in `batchOrderIds[marketId][batchId]`:

**Non-participating orders** (tick doesn't cross clearing price):
- **GoodTilBatch (GTB):** removed from book, full collateral refunded to wallet
- **GoodTilCancel (GTC):** left in book, rolled to next batch via `pushBatchOrderId()`

**Participating orders** (settled at clearing price, not order tick):
1. Compute pro-rata fill: `filledLots = (orderLots * matchedLots) / totalSideLots`
2. Filled collateral calculated at **clearing tick** (not the order's limit tick)
3. Excess refund = (collateral locked at order tick) - (cost at clearing tick)
4. Deduct fee (20 bps total, split 50/50): buy side pays `floor(fee/2)`, sell side pays `ceil(fee/2)` from USDT payout. Fees sent to protocol fee collector
5. Mint outcome token via `mintSingle()` (or credit internal position for `useInternalPositions` markets):
   - **Bidder** receives YES token (or YES position credit)
   - **Asker** receives NO token (or NO position credit)
6. Remove filled lots from order, update segment tree
7. **Fully filled or GTB:** withdraw unfilled collateral + excess refund to wallet
8. **Partially filled GTC:** roll remainder to next batch, withdraw excess refund if any

### Collateral Model (USDT)

Both sides lock USDT collateral (ERC-20). Users must approve the Vault before placing orders. Asks do NOT lock outcome tokens.
- Bid collateral: `lots * LOT_SIZE * tick / 100`
- Ask collateral: `lots * LOT_SIZE * (100 - tick) / 100`
- Sum per matched lot = LOT_SIZE (1e16 = $0.01), fully collateralized

### Clearing Price Settlement

All fills settle at the **clearing tick**, not the order's limit tick. This means:
- A bid at tick 70 filled at clearing tick 55 pays only 55% per lot (not 70%)
- The excess (70% - 55% = 15% per lot) is refunded to the bidder
- Same logic applies symmetrically to asks

### Chunked Settlement

Large batches settle across multiple `clearBatch` calls:

- **MAX_ORDERS_PER_BATCH = 1600** (up from 400 in v1.1)
- **SETTLE_CHUNK_SIZE = 400** — each `clearBatch` call settles up to 400 orders
- On the first call for a batch, clearing tick and matched lots are computed and stored as precomputed fills
- Subsequent calls reuse the precomputed fills and settle the next chunk of orders
- GTB orders that receive zero fills are cleaned up during settlement via `_tryRollOrCancel`

### Resting Order Handling

At the start of each `clearBatch`, `pullRestingOrders` is called to move in-range resting orders back into the segment tree before clearing. After settlement, GTC orders that are now far from the new clearing price are rolled to the resting list via `_tryRollOrCancel` instead of remaining in the active tree.

### Batch Overflow

`MAX_ORDERS_PER_BATCH = 1600`. When the current batch reaches 1600 orders, new orders automatically spill into the next batch. Placement fails only if both the current and next batch are full.

## Events

```solidity
event BatchCleared(uint256 indexed marketId, uint256 indexed batchId, uint256 clearingTick, uint256 matchedLots);
event OrderSettled(uint256 indexed orderId, address indexed owner, uint256 filledLots, uint256 collateralReleased);
```
