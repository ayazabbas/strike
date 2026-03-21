# Strike Protocol — Security Audit Report

**Date:** 2026-03-20
**Auditor:** Kalawd (AI-assisted manual review)
**Scope:** All 10 contracts in `src/` (2,286 lines Solidity)
**Framework:** 5C Security Model (Correctness, Confidentiality, Controls, Composability, Coverage)
**Contracts Version:** V8 (pre-mainnet)

---

## Executive Summary

The Strike protocol is a well-structured Frequent Batch Auction (FBA) prediction market. The architecture is sound — separation of concerns is clean (Vault, OrderBook, BatchAuction, MarketFactory, PythResolver, etc.) and storage packing is tight.

However, the audit identified **2 Critical**, **3 High**, **4 Medium**, and **6 Low/Informational** findings. The critical findings involve settlement ordering in `clearBatch` and a GTC rollover bug that can DoS batch clearing. Both must be fixed before mainnet.

### Severity Summary

| Severity | Count |
|----------|-------|
| 🔴 Critical | 2 |
| 🟠 High | 3 |
| 🟡 Medium | 4 |
| 🟢 Low / Informational | 6 |

---

## Findings

### 🔴 C-01: Sell Order Settlement Ordering Dependency (Critical)

**Category:** Correctness
**Affected:** `BatchAuction._settleSellOrder()`, `clearBatch()`

**Description:**
In `clearBatch()`, orders are settled sequentially in the order they appear in `batchOrderIds[]`. Buy order settlement adds collateral to `marketPool` via `vault.settleFill()`. Sell order settlement withdraws from `marketPool` via `vault.redeemFromPool()`.

If a sell order appears **before** the corresponding buy orders in the batch array, `redeemFromPool()` will revert because the pool hasn't been funded yet by the buy-side settlement.

```solidity
// clearBatch settles in array order:
for (uint256 i = 0; i < ids.length; i++) {
    _settleOrder(ids[i], result, fills[i]);  // sell before buy = revert
}
```

**Impact:** Batch clearing reverts entirely. Market becomes stuck — no orders can be filled. This is exploitable: a user can always place a sell order before any buy orders exist in a new batch, causing DoS.

**Scenario:**
1. Batch N clears, user receives YES tokens
2. New batch N+1: user places SellYes order (first in batch array)
3. Another user places Bid order (second in batch array)
4. `clearBatch(N+1)` → settles SellYes first → `redeemFromPool` reverts (pool empty for this batch's contribution)

Even if the pool has residual funds from prior batches, the amounts may not match (different clearing ticks across batches).

**Recommendation:** Two-pass settlement — settle all buy orders first (funding the pool), then settle all sell orders:

```solidity
// Pass 1: settle buy orders (fund pool)
for (uint256 i = 0; i < ids.length; i++) {
    if (!_isSellOrder(readOrder(ids[i]).side)) {
        _settleOrder(ids[i], result, fills[i]);
    }
}
// Pass 2: settle sell orders (withdraw from pool)
for (uint256 i = 0; i < ids.length; i++) {
    if (_isSellOrder(readOrder(ids[i]).side)) {
        _settleOrder(ids[i], result, fills[i]);
    }
}
```

---

### 🔴 C-02: GTC Partial Fill + Full Next Batch = clearBatch DoS (Critical)

**Category:** Correctness
**Affected:** `BatchAuction._tryRollOrCancel()`, `_settleBuyOrder()`, `_settleSellOrder()`

**Description:**
When a GTC order is partially filled, the settlement reduces on-chain lots by `filledLots`, then calls `_tryRollOrCancel()` with the original `OrderInfo` memory struct (which still has the original `lots` value). If the next batch is full (push fails), `_tryRollOrCancel` attempts `reduceOrderLots(orderId, o.lots)` using the **original** lot count, but the on-chain order now only has `originalLots - filledLots` remaining.

```solidity
// _settleBuyOrder (GTC partial):
orderBook.reduceOrderLots(orderId, s.filledLots);  // on-chain: lots = original - filled
// ...
_tryRollOrCancel(orderId, o, result.batchId + 1);  // o.lots = ORIGINAL (stale memory)

// _tryRollOrCancel:
if (!pushed) {
    orderBook.reduceOrderLots(orderId, o.lots);  // reverts: original > remaining
```

This causes `reduceOrderLots` to revert ("insufficient lots"), which reverts the entire `clearBatch()` transaction.

**Impact:** If any GTC order is partially filled in a batch and the next batch happens to be full (400 orders), the entire market's batch clearing is permanently DoS'd.

**Recommendation:** Pass remaining lots (not original) to `_tryRollOrCancel`, or compute remaining inside the function:

```solidity
// In _settleBuyOrder:
uint256 remainingLots = o.lots - s.filledLots;
OrderInfo memory remaining = o;
remaining.lots = remainingLots;
_tryRollOrCancel(orderId, remaining, result.batchId + 1);
```

Same fix needed in `_settleSellOrder`.

---

### 🟠 H-01: Emergency Withdraw Ignores Active Orders (High)

**Category:** Controls
**Affected:** `Vault.emergencyWithdraw()`

**Description:**
`emergencyWithdraw()` returns `balance[msg.sender]` (entire balance including locked portion) and zeros both `balance` and `locked`. If the user has active orders, those orders still reference locked collateral that has already been withdrawn. When those orders are later cancelled or settled, `vault.unlock()` / `vault.withdrawTo()` will operate on stale accounting.

```solidity
function emergencyWithdraw() external nonReentrant {
    require(emergencyMode, "Vault: not in emergency mode");
    require(block.timestamp >= emergencyActivatedAt + EMERGENCY_TIMELOCK, "Vault: timelock not elapsed");
    uint256 total = balance[msg.sender];
    balance[msg.sender] = 0;
    locked[msg.sender] = 0;  // zeroes lock, but orders still exist
    collateralToken.safeTransfer(msg.sender, total);
}
```

**Impact:** Double-withdrawal of collateral after emergency mode. Protocol insolvency if multiple users exploit this.

**Recommendation:** Emergency mode should either:
1. Force-cancel all active orders first, OR
2. Only allow withdrawal of `available(user)` (unlocked portion), OR
3. Document that emergency mode assumes all markets are dead (no further settlement)

---

### 🟠 H-02: No Fee on Sell Order Settlements (High)

**Category:** Correctness
**Affected:** `BatchAuction._settleSellOrder()`

**Description:**
Buy orders pay protocol fees on filled collateral via `_settleAmounts()`. Sell orders pay **zero fees** — the seller receives `_collateral(filledLots, clearingTick, side)` directly from the pool with no fee deduction.

```solidity
// _settleSellOrder:
uint256 payout = _collateral(filledLots, result.clearingTick, o.side);
vault.redeemFromPool(o.marketId, o.owner, payout);  // no fee!
```

**Impact:** Revenue leakage. Traders can avoid fees by buying tokens, then selling via sell orders instead of redeeming. This also creates an asymmetry that could be exploited for fee arbitrage.

**Recommendation:** Apply the same fee model to sell order payouts:
```solidity
uint256 grossPayout = _collateral(filledLots, result.clearingTick, o.side);
uint256 fee = feeModel.calculateFee(grossPayout);
uint256 netPayout = grossPayout - fee;
// Transfer fee to protocol fee collector
```

---

### 🟠 H-03: PythResolver Finality Window Too Short (High)

**Category:** Composability
**Affected:** `PythResolver.sol`

**Description:**
`FINALITY_BLOCKS = 3` on BSC (~3s blocks) gives only **~9 seconds** for challengers to submit alternative price data. This is likely insufficient for meaningful dispute resolution, especially considering:
- Challengers need to detect the submission, fetch alternative Pyth data, and submit a transaction
- BSC block times can vary under load
- The challenger must also pay Pyth oracle fees

**Impact:** First resolver effectively wins regardless of data quality, reducing the finality mechanism to a rubber stamp.

**Recommendation:** Increase to 20-50 blocks (~60-150 seconds) or use a time-based window instead of block-based.

---

### 🟡 M-01: closeMarket Should Clear Final Batch First (Medium)

**Category:** Correctness
**Affected:** `MarketFactory.closeMarket()`

**Description:**
`closeMarket()` deactivates the market in OrderBook without first clearing the current batch. Any orders in the active batch become stranded — they can't be settled via `clearBatch` (market deactivated) and can only be recovered via `cancelExpiredOrders()`.

**Impact:** Users with orders in the final batch lose their trading opportunity. The keeper is expected to `clearBatch` before `closeMarket`, but there's no on-chain enforcement.

**Recommendation:** Either:
1. Call `clearBatch` inside `closeMarket` before deactivation, OR
2. Allow `clearBatch` on deactivated markets for one final clearing, OR
3. Document this as a keeper responsibility with monitoring

---

### 🟡 M-02: Unbounded Array in placeOrders / cancelOrders (Medium)

**Category:** Correctness
**Affected:** `OrderBook.placeOrders()`, `OrderBook.cancelOrders()`, `OrderBook.replaceOrders()`

**Description:**
`params.length` and `orderIds.length` have no upper bound. While `MAX_ORDERS_PER_BATCH = 400` provides indirect protection for placements, cancel operations have no limit. A very large array could hit the block gas limit, causing unexpected reverts.

**Impact:** Gas griefing or accidental DoS if users submit oversized batches.

**Recommendation:** Add explicit bounds: `require(params.length <= 50, "too many orders")` or similar.

---

### 🟡 M-03: emergencyDrainPool Sends All Funds to Arbitrary Address (Medium)

**Category:** Controls
**Affected:** `Vault.emergencyDrainPool()`

**Description:**
After the 7-day timelock, `emergencyDrainPool` sends the entire market pool balance to an admin-specified address. There's no multi-sig requirement or per-market cap.

**Impact:** If admin key is compromised (even after 7-day delay), all market pools can be drained to attacker's address.

**Recommendation:** Consider requiring a multi-sig or implementing a per-call cap. At minimum, emit the recipient prominently so watchers can detect and respond.

---

### 🟡 M-04: Batch Overflow Doesn't Update currentBatchId (Medium)

**Category:** Correctness
**Affected:** `OrderBook.placeOrder()`, `OrderBook.placeOrders()`

**Description:**
When the current batch is full, orders overflow to `batchId + 1` but `market.currentBatchId` is NOT updated. This means `clearBatch` will process the original batch, advance to `currentBatchId + 1`, and the overflow orders will be in the correct next batch. However, there's a window where two batches accumulate orders simultaneously, and `clearBatch` might need to be called twice.

**Impact:** Potential confusion in batch tracking. Low risk in practice since the keeper calls `clearBatch` periodically.

**Recommendation:** Document this behavior. Consider auto-advancing `currentBatchId` on overflow.

---

### 🟢 L-01: PythResolver Uses Custom Admin Instead of AccessControl (Low)

**Category:** Controls
**Affected:** `PythResolver.sol`

**Description:**
All other contracts use OpenZeppelin `AccessControl` for role management. PythResolver uses a custom `admin` address with manual two-step transfer. This inconsistency increases cognitive load and missing features (no role admin hierarchy, no `renounceRole`).

**Recommendation:** Migrate to AccessControl for consistency.

---

### 🟢 L-02: No Event for Admin Transfer in PythResolver (Low)

**Category:** Controls
**Affected:** `PythResolver.setPendingAdmin()`, `PythResolver.acceptAdmin()`

**Description:**
Admin transfers emit no events, making them invisible to off-chain monitoring.

**Recommendation:** Add `AdminTransferInitiated` and `AdminTransferred` events.

---

### 🟢 L-03: marketMeta Public Getter Returns Tuple (Informational)

**Category:** Composability
**Affected:** `MarketFactory.marketMeta()`

**Description:**
The auto-generated getter for `marketMeta` returns an 8-element tuple. This is fragile for integrators — adding a new field changes the return signature.

**Recommendation:** Add explicit named getter functions for common queries.

---

### 🟢 L-04: FeeModel Rounding Favors Trader (Informational)

**Category:** Correctness
**Affected:** `FeeModel.calculateFee()`

**Description:**
`(amount * feeBps) / MAX_BPS` rounds down (Solidity default). The protocol collects slightly less than intended on small amounts.

**Impact:** Negligible revenue loss. Standard pattern.

**Recommendation:** Consider rounding up for protocol fees: `(amount * feeBps + MAX_BPS - 1) / MAX_BPS`.

---

### 🟢 L-05: OutcomeToken URI Is Empty (Informational)

**Category:** Composability
**Affected:** `OutcomeToken.sol`

**Description:**
`ERC1155("")` sets an empty URI. While outcome tokens aren't meant for secondary trading, some block explorers and wallets display ERC1155 tokens and would show no metadata.

**Recommendation:** Set a base URI pointing to market metadata.

---

### 🟢 L-06: No Pausability on OrderBook or BatchAuction (Low)

**Category:** Controls
**Affected:** `OrderBook.sol`, `BatchAuction.sol`

**Description:**
`MarketFactory` has `pauseFactory()` to prevent new market creation. However, there's no global pause on `OrderBook` (only per-market halt) or `BatchAuction`. In an emergency, admin must halt each market individually.

**Recommendation:** Add a global pause inherited from `Pausable` on OrderBook and BatchAuction.

---

## Architecture Review

### Trust Assumptions

```
User → OrderBook (placeOrder/cancel) → Vault (deposit/lock)
                                     → OutcomeToken (ERC1155 transfer for sells)

Keeper → BatchAuction (clearBatch) → OrderBook (OPERATOR_ROLE)
                                   → Vault (PROTOCOL_ROLE)
                                   → OutcomeToken (MINTER_ROLE, ESCROW_ROLE)

Keeper → MarketFactory (MARKET_CREATOR_ROLE) → OrderBook (OPERATOR_ROLE)

Anyone → PythResolver (resolveMarket) → MarketFactory (ADMIN_ROLE)

Anyone → Redemption (redeem) → OutcomeToken (MINTER_ROLE)
                              → Vault (PROTOCOL_ROLE)
```

**Key roles:**
- `OPERATOR_ROLE` on OrderBook: held by BatchAuction + MarketFactory
- `PROTOCOL_ROLE` on Vault: held by OrderBook + BatchAuction + Redemption
- `MINTER_ROLE` on OutcomeToken: held by BatchAuction + Redemption
- `ESCROW_ROLE` on OutcomeToken: held by BatchAuction
- `MARKET_CREATOR_ROLE` on MarketFactory: held by keeper wallet
- `ADMIN_ROLE` on MarketFactory: held by PythResolver + admin

### Reentrancy Protection
- Vault: `ReentrancyGuard` ✅
- OrderBook: `ReentrancyGuard` ✅
- BatchAuction: `ReentrancyGuard` ✅
- Redemption: `ReentrancyGuard` ✅
- PythResolver: `ReentrancyGuard` ✅
- MarketFactory: `ReentrancyGuard` ✅
- FeeModel: None (no external calls, stateless calc) ✅
- SegmentTree: Library (no external calls) ✅

### Storage Packing
Excellent — Order (2 slots), BatchResult (2 slots), Market (1 slot). Well-optimized for gas.

---

## Gas Optimizations

1. **`_computeFills` reads orders twice** — once in `_computeFills` and again in `_settleOrder`. Cache order data to avoid double SLOAD.

2. **`batchOrderIds` array iteration** — `clearBatch` iterates the full array twice (fills + settlement). Consider combining into single pass (after fixing C-01).

3. **`SegmentTree.prefixSum` recursive calls** — The recursive `_rangeQuery` uses stack frames. An iterative bottom-up approach would save gas on deep trees.

4. **`settleFill` compound operation** — Well-designed for gas savings. No changes needed.

---

## Recommendations (Prioritized)

1. **🔴 Fix C-01** — Two-pass settlement (buy first, then sell) in `clearBatch`
2. **🔴 Fix C-02** — Pass remaining lots (not original) to `_tryRollOrCancel`
3. **🟠 Fix H-02** — Add fee to sell order settlements
4. **🟠 Fix H-01** — Constrain emergency withdrawal to available balance or force-cancel orders
5. **🟠 Fix H-03** — Increase finality window to 20-50 blocks
6. **🟡 Fix M-01** — Enforce final batch clear before market close
7. **🟡 Fix M-02** — Add upper bound to batch operation array sizes
8. **🟢 Address remaining Low/Informational items before mainnet

---

## Conclusion

The protocol demonstrates strong fundamentals — the FBA model is well-implemented, storage is efficiently packed, and role-based access control is properly layered. The critical findings (C-01 and C-02) are settlement-path bugs that would manifest under specific but realistic conditions. They must be fixed before mainnet deployment. The fee gap on sell orders (H-02) should also be addressed as it creates an exploitable asymmetry.

After these fixes, a follow-up review focusing on the modified settlement logic is recommended.
