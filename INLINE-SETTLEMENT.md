# Inline Settlement — Implementation Plan

## Goal
Fold `claimFills` settlement logic into `clearBatch` so orders are settled atomically when the batch clears. Users place an order, walk away, tokens and refunds just appear. No separate claim step.

## Design: Keeper Passes Order IDs via Calldata

The keeper/indexer already knows every order in a batch. We pass the order IDs as calldata to `clearBatch`, and the contract verifies + settles each one inline.

## Changes Required

### 1. BatchAuction.sol

**Change `clearBatch` signature:**
```solidity
function clearBatch(uint256 marketId, uint256[] calldata orderIds) external returns (BatchResult memory result)
```

**After computing clearing tick + matched lots, add settlement loop:**
```solidity
// After storing batchResults and advancing batch...
for (uint256 i = 0; i < orderIds.length; i++) {
    _settleOrder(orderIds[i], result);
}
```

**Add internal `_settleOrder` function** — extract the core logic from current `claimFills`:
- Read order, verify it belongs to this market + current batch
- Calculate pro-rata fill
- For GTC partial fills: reduce lots, leave unfilled resting in the book
- For GTB or GTC full fills: remove entire order
- Settle vault (filled collateral → market pool, unfilled → unlock, protocol fee)
- Mint outcome tokens (BID → YES, ASK → NO)
- Emit FillClaimed event

**Keep `claimFills` as a public fallback** — for any orders the keeper missed (belt + suspenders). No functional change to existing claimFills.

**Add validation in settlement loop:**
- `require(order.marketId == marketId)` — order belongs to this market
- `require(order.batchId == result.batchId)` — order is from the batch being cleared
- `require(order.lots > 0)` — order hasn't already been settled
- Mark order as claimed (set lastClaimedBatch) to prevent double-settle via fallback claimFills

### 2. OrderBook.sol — No changes needed
Orders are already readable by ID. `reduceOrderLots` and `updateTreeVolume` are already OPERATOR_ROLE callable.

### 3. Vault.sol — No changes needed
`settleFill` and `unlock` are already PROTOCOL_ROLE callable.

### 4. Keeper (strike-infra/batch-keeper)
- Query indexer for all order IDs in the current batch before clearing
- Pass order IDs array to the new `clearBatch(marketId, orderIds)` signature
- Remove any separate claimFills logic (if it existed)

### 5. Tests
- Update all `clearBatch` calls in tests to pass order ID arrays
- Add test: clearBatch with settlement verifies token balances + vault state
- Add test: clearBatch with empty orderIds array (no orders to settle, still clears)
- Add test: orders not in the batch are rejected
- Add test: fallback claimFills still works for orders not in the calldata array
- Gas comparison: measure new clearBatch vs old clearBatch + N×claimFills

### 6. E2E Tests (strike-infra)
- Update e2e test scenarios to verify settlement happens inline (no separate claim step)
- Verify outcome token balances appear immediately after clearBatch

### 7. Frontend
- Remove any "claim fills" UI/logic — settlement is automatic now
- Order status goes directly from "pending" → "filled" after batch clear

## Gas Estimates
From our gas report (devnet measurements):
- Current: clearBatch (307k) + N × claimFills (~150k each)
- Projected: clearBatch (~307k + N × ~130k inline) — saves ~20k per order (no tx overhead + shared SLOADs)
- 10 orders: ~1.6M gas ($0.96 @ 1 gwei) vs current ~1.8M ($1.08)
- Block gas limit (BNB): 140M — can handle ~1,000 orders per batch

## Order of Implementation
1. Refactor BatchAuction.sol (extract `_settleOrder`, modify `clearBatch`)
2. Update unit tests (forge)
3. Update batch-keeper Rust service
4. Update e2e tests
5. Update frontend (remove claim UI)
6. Re-run gas report to verify savings
