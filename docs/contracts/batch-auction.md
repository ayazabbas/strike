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
4. Deduct uniform fee (20 bps) on filled collateral, send to protocol fee collector
5. Mint outcome token via `mintSingle()`:
   - **Bidder** receives YES token
   - **Asker** receives NO token
6. Remove filled lots from order, update segment tree
7. **Fully filled or GTB:** withdraw unfilled collateral + excess refund to wallet
8. **Partially filled GTC:** roll remainder to next batch, withdraw excess refund if any

### Collateral Model (USDT)

Both sides lock USDT collateral (ERC-20). Users must approve the Vault before placing orders. Asks do NOT lock outcome tokens.
- Bid collateral: `lots * LOT_SIZE * tick / 100`
- Ask collateral: `lots * LOT_SIZE * (100 - tick) / 100`
- Sum per matched lot = LOT_SIZE (1e18 = 1 USDT), fully collateralized

### Clearing Price Settlement

All fills settle at the **clearing tick**, not the order's limit tick. This means:
- A bid at tick 70 filled at clearing tick 55 pays only 55% per lot (not 70%)
- The excess (70% - 55% = 15% per lot) is refunded to the bidder
- Same logic applies symmetrically to asks

### Batch Overflow

`MAX_ORDERS_PER_BATCH = 400`. When the current batch reaches 400 orders, new orders automatically spill into the next batch. Placement fails only if both the current and next batch are full.

## Events

```solidity
event BatchCleared(uint256 indexed marketId, uint256 indexed batchId, uint256 clearingTick, uint256 matchedLots);
event OrderSettled(uint256 indexed orderId, address indexed owner, uint256 filledLots, uint256 collateralReleased);
```
