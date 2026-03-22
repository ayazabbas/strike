# Internal Security Audit — v1.2

**Date:** 2026-03-22
**Auditor:** Internal (pre-mainnet review)
**Scope:** All Solidity files in `contracts/src/` (~2,750 lines across 10 files)
**Commit:** v1.2 (post-fix round: per-user caps, proximity filtering, chunked settlement, fee split, GTB zero-fill cleanup, GTC roll-to-resting)
**Test suite:** 338 tests, all passing

---

## Summary

This audit covers ~400 new lines introduced in v1.2 across `OrderBook.sol` and `BatchAuction.sol`, plus supporting changes in `FeeModel.sol`. The new features — per-user order caps, price-proximity batch filtering, chunked settlement, 50/50 fee split, GTB zero-fill cleanup, and GTC roll-to-resting — are well-structured and tested.

**1 Medium** finding (DoS vector via resting array scan), **1 Medium** latent bug (stale lots in unreachable code path), **5 Low** findings, and **3 Informational** observations were identified. No critical vulnerabilities were found. All v1.1 audit findings have been verified as fixed.

---

## Findings Summary

| ID | Title | Severity | Contract |
|----|-------|----------|----------|
| M-01 | `pullRestingOrders` full-array scan can DoS `clearBatch` | Medium | OrderBook |
| M-02 | Stale `o.lots` in `_tryRollOrCancel` after partial fill (latent) | Medium | BatchAuction |
| L-01 | `_hasPrecomputed` mapping written but never read | Low | BatchAuction |
| L-02 | `restingScanIndex` mapping declared but never used | Low | OrderBook |
| L-03 | Defensive floor-at-zero in `activeOrderCount` decrement masks drift | Low | OrderBook |
| L-04 | Batch overflow check over-counts when some orders go to resting | Low | OrderBook |
| L-05 | Public function `_isTickFar` uses internal naming convention | Low | OrderBook |
| I-01 | `pullRestingOrders` can push current batch beyond `MAX_ORDERS_PER_BATCH` | Info | OrderBook |
| I-02 | Resting array lazy compaction allows unbounded growth between clears | Info | OrderBook |
| I-03 | Permissionless `clearBatch` MEV exposure (documented, accepted) | Info | BatchAuction |

---

## Detailed Findings

### M-01: `pullRestingOrders` full-array scan can DoS `clearBatch`

**Contract:** `OrderBook.sol` — `pullRestingOrders()` (line 667)

**Description:**
`pullRestingOrders` iterates the entire `restingOrderIds[marketId]` array on every call, regardless of `MAX_RESTING_PULL`. While it only *pulls* at most 200 orders into the active batch, it reads every entry in the array (2 SLOADs per entry: one for the order ID, one for the order's lots).

```solidity
for (uint256 i = 0; i < len; ) {       // scans ALL entries
    uint256 oid = resting[i];
    Order storage o = orders[oid];
    if (o.lots == 0) { ... }
    else if (pulled < MAX_RESTING_PULL && _isTickNear(...)) { ... }
    else { writeIdx++; }                // compact forward
}
```

Since `pullRestingOrders` is called by `clearBatch` before every clearing price computation, a sufficiently large resting array makes `clearBatch` exceed BSC's block gas limit (~140M gas), effectively DoS-ing the market.

**Impact:**
An attacker can park many orders from many addresses (each user can have up to 20 resting orders per market at minimum cost of 1 lot = $0.01). At ~6,000 gas per iteration, the gas limit is reached at ~23,000 entries, requiring ~1,150 unique addresses. The attack is cheap in dollar terms but requires coordination.

The declared-but-unused `restingScanIndex` mapping suggests paginated scanning was planned but not implemented.

**Proof of concept:**
1. Establish a clearing tick at 50 via a normal Bid/Ask match.
2. From 1,200 unique addresses, each place 20 GTC Bid orders at tick 1 (far from 50, goes to resting).
3. Resting array grows to 24,000 entries.
4. `clearBatch` reverts due to gas limit on the `pullRestingOrders` scan.
5. Market cannot clear batches until resting orders are individually cancelled.

**Recommended fix:**
Implement paginated scanning using `restingScanIndex`:
```solidity
function pullRestingOrders(uint256 marketId) external onlyRole(OPERATOR_ROLE) returns (uint256 pulled) {
    uint256[] storage resting = restingOrderIds[marketId];
    uint256 len = resting.length;
    if (len == 0) return 0;

    uint256 startIdx = restingScanIndex[marketId];
    if (startIdx >= len) startIdx = 0;

    uint256 batchId = markets[marketId].currentBatchId;
    uint256 scanned;
    uint256 maxScan = 400; // bound total iterations per call

    for (uint256 i = startIdx; scanned < maxScan && scanned < len; ) {
        // ... same logic but with bounded iteration ...
        scanned++;
        i = (i + 1) % len;
    }

    restingScanIndex[marketId] = (startIdx + scanned) % len;
    // compact separately or lazily
}
```

---

### M-02: Stale `o.lots` in `_tryRollOrCancel` after partial fill (latent)

**Contract:** `BatchAuction.sol` — `_settleBuyOrder()` (line 502), `_settleSellOrder()` (line 571)

**Description:**
When a GTC order is partially filled, the settlement code reduces the order's lots in storage and updates the tree volume, then calls `_tryRollOrCancel` with the original `OrderInfo` (from memory):

```solidity
// _settleBuyOrder partial fill path:
orderBook.reduceOrderLots(orderId, s.filledLots);          // storage: lots -= filledLots
orderBook.updateTreeVolume(..., -int256(s.filledLots));     // tree: -= filledLots
// ... vault settlement ...
_tryRollOrCancel(orderId, o, result.batchId + 1);           // o.lots = ORIGINAL lots
```

Inside `_tryRollOrCancel`, if `_isTickFar` returns true:
```solidity
orderBook.removeFromTree(o.marketId, o.side, o.tick, o.lots);  // removes ORIGINAL lots
```

This would over-remove from the tree by `filledLots`, corrupting tree state.

**Current reachability:** **Unreachable.** A participating order (one with a fill) has a tick at or better than the clearing tick. `_isTickFar` compares against the clearing tick as reference, so a participating order's tick is always within proximity. The `else` branch (roll to next batch, no tree removal) is always taken.

**Impact:**
No current impact. However, if the proximity threshold logic, clearing tick update ordering, or participation rules are modified in a future version, this becomes a critical tree corruption bug leading to incorrect clearing prices and potential fund loss.

**Recommended fix:**
Pass the remaining lots (after partial fill) instead of the original OrderInfo:
```solidity
// After partial fill:
OrderInfo memory remaining = o;
remaining.lots = o.lots - s.filledLots;
_tryRollOrCancel(orderId, remaining, result.batchId + 1);
```

---

### L-01: `_hasPrecomputed` mapping written but never read

**Contract:** `BatchAuction.sol` — line 42

**Description:**
The mapping `_hasPrecomputed` is written to during the first settlement chunk (line 205) and deleted during the final chunk (line 229), but its value is never read anywhere in the codebase. This wastes ~5,000 gas per SSTORE on each order during chunked settlement.

**Recommended fix:**
Remove the `_hasPrecomputed` mapping entirely. The `_precomputedFills` mapping alone is sufficient — a zero fill is a valid precomputed value (zero-fill orders are handled correctly by the settlement logic).

---

### L-02: `restingScanIndex` mapping declared but never used

**Contract:** `OrderBook.sol` — line 61

**Description:**
```solidity
mapping(uint256 => uint256) public restingScanIndex;
```
This mapping occupies a storage slot declaration but is never read or written. It appears to be scaffolding for paginated resting list scanning (see M-01) that was not implemented.

**Recommended fix:**
Either implement paginated scanning (addressing M-01) or remove the dead declaration to reduce confusion.

---

### L-03: Defensive floor-at-zero in `activeOrderCount` decrement masks drift

**Contract:** `OrderBook.sol` — lines 259, 468, 609

**Description:**
All three decrement sites use a floor-at-zero guard:
```solidity
if (activeOrderCount[user][marketId] > 0) {
    activeOrderCount[user][marketId]--;
}
```

While defensive, this silently absorbs any counter drift bug instead of reverting. If the counter ever becomes inconsistent (e.g., due to a future code change that adds a decrement path without a matching increment), the guard would clip to 0 without alerting anyone, potentially allowing users to place unlimited orders.

**Recommended fix:**
Consider reverting on underflow during development/testing, and only using the floor-at-zero pattern in production if the invariant is verified by tests:
```solidity
require(activeOrderCount[user][marketId] > 0, "OrderBook: counter underflow");
activeOrderCount[user][marketId]--;
```

---

### L-04: Batch overflow check over-counts when some orders go to resting

**Contract:** `OrderBook.sol` — `placeOrders()` (line 374), `replaceOrders()` (line 423)

**Description:**
The batch overflow check assumes all orders in `params` will be added to the batch:
```solidity
if (batchOrderIds[marketId][batchId].length + params.length > MAX_ORDERS_PER_BATCH) {
    batchId = batchId + 1;
}
```

However, orders with ticks far from the clearing price go to the resting list instead. The check over-counts, potentially forcing a batch overflow when the batch would actually fit.

**Impact:**
Users may be unable to place valid batch orders when the batch is near capacity but some of their orders would go to resting. Annoying UX but no fund risk.

**Recommended fix:**
This is a trade-off between gas (pre-counting near/far orders) and UX. The current conservative approach is acceptable for v1. Consider documenting this behavior for frontend order submission logic.

---

### L-05: Public function `_isTickFar` uses internal naming convention

**Contract:** `OrderBook.sol` — line 641

**Description:**
```solidity
function _isTickFar(uint256 marketId, uint256 tick, Side side) public view returns (bool) {
```

The underscore prefix conventionally indicates an internal/private function, but `_isTickFar` is `public` because `BatchAuction._tryRollOrCancel` calls it cross-contract. This naming is misleading for auditors and integrators.

**Recommended fix:**
Rename to `isTickFar` (without underscore) to match its public visibility.

---

### I-01: `pullRestingOrders` can push beyond `MAX_ORDERS_PER_BATCH`

**Contract:** `OrderBook.sol` — `pullRestingOrders()` (line 689)

**Description:**
When resting orders are pulled into the current batch, no check enforces `MAX_ORDERS_PER_BATCH` on the resulting batch size. This is by design — the comment on `pushBatchOrderId` states "No cap — chunked clearBatch handles arbitrarily large batches." The chunked settlement mechanism (SETTLE_CHUNK_SIZE = 400) handles batches of any size.

**Recommendation:** No action needed. The design is intentional and sound.

---

### I-02: Resting array lazy compaction allows growth between clears

**Contract:** `OrderBook.sol`

**Description:**
When resting orders are cancelled, the order ID remains in `restingOrderIds` and is only removed during the next `pullRestingOrders` scan. Between batch clears, the array can grow with stale entries. This is mitigated by `MAX_USER_ORDERS = 20` bounding per-user contributions and by the compaction that occurs during each `pullRestingOrders` call.

**Recommendation:** Acceptable for v1. Monitor resting array sizes in production via events/indexer.

---

### I-03: Permissionless `clearBatch` MEV exposure (documented)

**Contract:** `BatchAuction.sol` — `clearBatch()` (line 102)

**Description:**
The NatSpec on `clearBatch` documents the known MEV vector: anyone can call `clearBatch` at any time, enabling sandwich attacks that isolate users in nearly-empty batches. Price-proximity filtering (v1.2) mitigates this by keeping only near-price orders active.

**Recommendation:** Already documented and accepted. Future mitigation: enforce minimum batch duration or restrict to permissioned keeper. Consider adding this to the external-facing security documentation.

---

## Verification of v1.1 Fixes

All v1.1 audit findings have been verified as properly fixed with dedicated test coverage in `AuditFixes.t.sol`:

| v1.1 Finding | Fix | Verification |
|---------------|-----|-------------|
| **M-01: GTB zero-fill stuck orders** | GTB orders at clearing tick with 0 fill (pro-rata rounding) are now cleaned up: lots zeroed, tree updated, collateral/tokens returned. | `test_Fix1_GTBBuyZeroFillCleanedUp`, `test_Fix1_GTBSellZeroFillCleanedUp`, `test_Fix1_GTBInternalPositionsZeroFillCleanedUp` |
| **I-01: Uniform fee favors sell side** | Fees split 50/50: buy side pays `calculateOtherHalfFee` (floor half), sell side pays `calculateHalfFee` (ceil half). Sum equals full fee for all inputs. | `test_Fix5_EqualFeesBothSides`, `test_Fix5_TotalFeePreserved`, `test_Fix5_OddWeiRoundingToProtocol`, `test_Fix5_SolvencyFuzz` |
| **L-01: Chunked settlement correctness** | `_precomputedFills` mapping stores fills during first chunk; subsequent chunks read stored fills and re-read OrderInfo from storage via `_readOrder`. | `test_Fix2_MultiChunkSettlement`, `test_Fix2_GTC_PartialFillAcrossChunks`, `test_PostReview1_MultiChunkBothSidesGTC`, `test_PostReview1_ChunkSettlesCorrectOwnerAndTick` |
| **L-02: MAX_ORDERS_PER_BATCH too low** | Raised from 400 to 1600 (4 × SETTLE_CHUNK_SIZE). | `test_Fix3_MaxOrdersPerBatchIs1600` |
| **L-03: MEV on clearBatch** | Documented in NatSpec. Price-proximity filtering reduces attack surface. | Code review verified. |
| **Fix 4a: Price-proximity filtering** | Far-from-price orders parked in resting list, pulled back via gas-bounded `pullRestingOrders`. | `test_Fix4a_FarOrderParked`, `test_Fix4a_NearOrderActive`, `test_Fix4a_PullInWhenPriceMoves`, `test_Fix4a_CancelRestingOrder`, `test_Fix4a_GTC_RollToResting`, `test_Fix4a_LazySkipCancelled` |
| **Fix 4b: Per-user order cap** | `MAX_USER_ORDERS = 20` per market, tracked via `activeOrderCount`. Enforced on placement, decremented on cancel/fill/expire. | `test_Fix4b_CapHitReverts`, `test_Fix4b_CancelAllowsNewPlacement`, `test_Fix4b_FillDecrementsCount` |
| **Post-review: batch proximity** | `placeOrders` and `replaceOrders` use `_isTickFar` per order (via `_placeOne`). | `test_PostReview2_PlaceOrdersBatchProximity`, `test_PostReview2_ReplaceOrdersFarGoToResting`, `test_PostReview2_PlaceOrdersFarAskResting` |
| **Post-review: deduplicated proximity** | `BatchAuction._tryRollOrCancel` calls `orderBook._isTickFar` (single source of truth). | `test_PostReview3_BatchAuctionUsesOrderBookProximity` |

---

## Invariant Analysis

### `activeOrderCount` Invariant

**Claim:** For every `(user, marketId)`, `activeOrderCount[user][marketId]` equals the number of orders where `orders[id].owner == user && orders[id].marketId == marketId && orders[id].lots > 0`.

**Verification by path analysis:**

| Code Path | Increment | Decrement | Correct |
|-----------|-----------|-----------|---------|
| `placeOrder` | +1 at placement | — | Order created with lots > 0 |
| `placeOrders` | +params.length | — | All orders created with lots > 0 |
| `replaceOrders` | +params.length (new), -1 per cancel | -1 per cancelled order | Net correct |
| `cancelOrder` / `cancelOrders` | — | -1 | lots set to 0 |
| `cancelExpiredOrder` | — | -1 via `_cancelCore` | lots set to 0 |
| GTB fully filled | — | -1 via `decrementActiveOrderCount` | lots set to 0 |
| GTC fully filled | — | -1 via `decrementActiveOrderCount` | lots set to 0 |
| GTB non-participating | — | -1 via `decrementActiveOrderCount` | lots set to 0, collateral returned |
| GTB zero-fill cleanup | — | -1 via `decrementActiveOrderCount` | lots set to 0, collateral returned |
| GTC non-participating | — | No decrement | lots > 0, order rolls (still active) |
| GTC zero-fill | — | No decrement | lots > 0, order rolls (still active) |
| GTC partial fill | — | No decrement | lots reduced but > 0, order rolls |

**Result:** Invariant holds across all code paths. The floor-at-zero guard (L-03) adds resilience but masks potential bugs.

### Resting State Invariant

**Claim:** `isResting[id] == true` iff the order is in `restingOrderIds` AND NOT in the SegmentTree AND NOT in `batchOrderIds` for the current batch.

**Verification:**

| Transition | `isResting` | Array | Tree | Batch | Consistent |
|-----------|-------------|-------|------|-------|------------|
| Place → resting | set true | pushed | NOT added | NOT pushed | Yes |
| Pull → active | set false | removed (compact) | added | pushed | Yes |
| Cancel resting | set false | lazy-skipped later | was never in tree | N/A | Yes |
| GTC roll → resting | set true (via `pushRestingOrderId`) | pushed | removed (via `removeFromTree`) | not in new batch | Yes |

**Result:** Invariant holds. Lazy removal from the array is safe because `pullRestingOrders` skips cancelled orders (lots == 0) and clears their `isResting` flag.

### Pool Solvency with Fee Split

**Claim:** `vault.marketPool[marketId] >= sum of all outstanding token obligations` at all times during normal operation.

**Analysis:**

For a Bid/Ask match at clearing tick C:
- Pool receives: `lots * LOT_SIZE * C/100` (from Bid) + `lots * LOT_SIZE * (100-C)/100` (from Ask) = `lots * LOT_SIZE`
- Fees are deducted from users' locked collateral (buy-side fee) and from seller's pool payout (sell-side fee), NOT from the pool's principal.

For a SellYes/Bid match at clearing tick C:
- Pool receives: `lots * LOT_SIZE * C/100` (from new Bid's `s.toPool`)
- Pool pays out: `lots * LOT_SIZE * C/100` (grossPayout to SellYes, split between seller payout and sell fee)
- Net pool change: 0. The YES tokens are burned and new YES tokens are minted. Token count unchanged, pool unchanged.
- Sell-side fee is paid from the seller's share of the pool payout, then transferred to fee collector also from pool. Total outflow = grossPayout (unchanged from pre-fee-split).

For a SellNo/Ask match: symmetric analysis. Net pool change: 0.

**Algebraic verification of fee sum:**
```
calculateHalfFee(x)      = ceil(fullFee / 2) = (fullFee + 1) / 2
calculateOtherHalfFee(x) = fullFee - ceil(fullFee / 2)
Sum = fullFee ✓ (for all x)
```

**Fuzz test coverage:** `test_Fix5_SolvencyFuzz` verifies `pool >= lots * LOT_SIZE` across all tick/lot combinations.

**Result:** Pool solvency is maintained. The fee split does not alter the pool's principal — fees come from user-locked excess collateral (buy side) and from seller's payout share (sell side).

---

## Test Coverage Assessment

| Area | Tests | Coverage Quality |
|------|-------|-----------------|
| Per-user order cap | 3 tests | Good: cap enforcement, cancel-reopen, fill-decrement |
| Price-proximity filtering | 8 tests | Good: park, pull-in, cancel-resting, GTC-roll, lazy-skip, events, batch placement |
| Chunked settlement | 4 tests | Good: multi-chunk, partial fill, both-sides GTC, correct owner/tick in later chunks |
| GTB zero-fill cleanup | 3 tests | Good: buy, sell, internal positions |
| Fee split | 4 tests (inc. fuzz) | Good: both sides, total preserved, odd-wei rounding, solvency fuzz |
| MAX_ORDERS_PER_BATCH | 1 test | Adequate: constant value check |
| GTC roll-to-resting | 1 test | Minimal: only tests the happy path |

**Gaps identified:**
- No test for `pullRestingOrders` with a large resting array (gas limit behavior)
- No test for `pullRestingOrders` when MAX_RESTING_PULL is reached (partial pull)
- No test for resting order interaction with `cancelExpiredOrders`
- No test for chunked settlement with sell orders in later chunks
- No fuzz test for `_isTickFar` boundary conditions
- No test verifying `activeOrderCount` invariant after complex multi-batch sequences

---

## Overall Risk Assessment

**Risk level: LOW-MEDIUM**

The v1.2 changes are well-implemented with good test coverage. The primary concern is M-01 (resting array DoS), which is economically cheap to execute on BSC. The latent bug in M-02 is currently unreachable but should be fixed before any refactoring of the proximity or clearing logic.

**Recommendations before mainnet:**

1. **Fix M-01** — Implement paginated resting array scanning to eliminate the DoS vector. This is the only finding that could disrupt live market operations.
2. **Fix M-02** — Pass remaining lots (not original) to `_tryRollOrCancel`. Cheap fix that eliminates a latent critical bug.
3. **Fix L-01** — Remove dead `_hasPrecomputed` mapping to save ~5,000 gas per order during chunked settlement.
4. **Fix L-02** — Either implement paginated scanning (part of M-01 fix) or remove `restingScanIndex`.
5. **Add tests** for the identified coverage gaps, especially large resting arrays and sell orders in later settlement chunks.
6. **Consider** restricting `clearBatch` to a permissioned keeper or enforcing minimum batch duration to reduce MEV surface (I-03).
