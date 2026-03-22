# Internal Security Audit — v1.2

**Date:** 2026-03-22
**Auditor:** Internal Security Review
**Scope:** All Solidity contracts in `contracts/src/` (10 files, ~2,780 lines)
**Framework:** Solidity ^0.8.25, Foundry
**Chain:** BNB Chain (BSC)
**Test Suite:** 347 tests, all passing

---

## Executive Summary

This report covers the full v1.2 codebase of the Strike prediction market protocol after all fixes from the initial v1.2 audit pass have been applied (commit `9abf674`). The protocol implements a binary outcome CLOB with Frequent Batch Auctions, ERC-20 collateral escrow, ERC-1155 outcome tokens, and Pyth Core oracle resolution.

v1.2 introduced per-user active order caps, price-proximity resting lists with paginated scanning, chunked settlement with precomputed fills, and a 50/50 buy/sell fee split. All findings from the v1.1 audit and the initial v1.2 audit pass have been addressed or formally acknowledged.

**Current findings: 0 Critical, 0 High, 0 Medium, 2 Low, 2 Informational.**

**Overall Risk Assessment: LOW.** The codebase is well-structured with correct accounting invariants, comprehensive access control, and strong test coverage. Remaining findings are low-impact code quality items and acknowledged architectural decisions.

---

## Scope

| Contract | File | Lines | Description |
|----------|------|------:|-------------|
| ITypes | `src/ITypes.sol` | 82 | Shared types, enums, structs, `LOT_SIZE` constant |
| SegmentTree | `src/SegmentTree.sol` | 199 | O(log N) segment tree library for 99-tick orderbook |
| OrderBook | `src/OrderBook.sol` | 761 | Order placement, cancellation, resting list, segment trees |
| BatchAuction | `src/BatchAuction.sol` | 599 | Batch clearing, chunked settlement, precomputed fills |
| Vault | `src/Vault.sol` | 255 | USDT collateral escrow, lock/unlock, market pool, emergency withdrawal |
| MarketFactory | `src/MarketFactory.sol` | 308 | Market lifecycle, permissioned creation, state transitions |
| FeeModel | `src/FeeModel.sol` | 85 | Uniform fee calculation with 50/50 buy/sell split |
| OutcomeToken | `src/OutcomeToken.sol` | 139 | ERC-1155 YES/NO tokens, escrow burn |
| PythResolver | `src/PythResolver.sol` | 269 | Pyth Core oracle resolution with finality gate |
| Redemption | `src/Redemption.sol` | 82 | Post-resolution token redemption |
| **Total** | | **~2,780** | |

---

## Architecture Overview

### Protocol Description

Strike is a fully on-chain binary outcome prediction market. Traders buy/sell YES/NO outcome tokens at price ticks 1–99 (each tick = 1% probability). Orders feed into Frequent Batch Auctions where a uniform clearing price is computed via segment tree aggregation. All fills settle at the clearing tick, not the limit tick. Collateral is USDT (ERC-20) held by the Vault; outcome tokens are ERC-1155 or internal positions.

### Trust Boundary Diagram

```
                           ┌──────────────┐
                           │   Users      │
                           └──────┬───────┘
                                  │ approve + placeOrder/cancel/redeem
                           ┌──────▼───────┐
                           │  OrderBook   │◄──── ERC1155Holder (sell order custody)
                           └──────┬───────┘
                      OPERATOR_ROLE│
                           ┌──────▼───────┐
                           │ BatchAuction │
                           └──┬────┬──┬───┘
              PROTOCOL_ROLE   │    │  │ MINTER_ROLE / ESCROW_ROLE
                ┌─────────────▼┐ ┌▼──▼──────────┐
                │    Vault     │ │ OutcomeToken  │
                └──────────────┘ └───────────────┘
                                        ▲
                           ┌────────────┘ MINTER_ROLE
                           │
                    ┌──────▼───────┐      ┌──────────────┐
                    │  Redemption  │      │ PythResolver │
                    └──────────────┘      └──────────────┘
                                                 │
                           ┌─────────────────────▼──┐
                           │    MarketFactory       │
                           └────────────────────────┘
```

### Access Control Summary

| Role | Contract | Grantees |
|------|----------|----------|
| `OPERATOR_ROLE` | OrderBook | BatchAuction, MarketFactory |
| `PROTOCOL_ROLE` | Vault | OrderBook, BatchAuction, Redemption |
| `MINTER_ROLE` | OutcomeToken | BatchAuction, Redemption |
| `ESCROW_ROLE` | OutcomeToken | BatchAuction |
| `MARKET_CREATOR_ROLE` | MarketFactory | Authorized market creators |
| `ADMIN_ROLE` | MarketFactory | PythResolver, admin |
| `DEFAULT_ADMIN_ROLE` | All AccessControl contracts | Deployer/admin multisig |

All role-gated functions verified correct. No privilege escalation paths identified.

---

## Findings

### Summary Table

| ID | Title | Severity | Status |
|----|-------|----------|--------|
| L-01 | `uint16` cast on `params.length` in batch operations | Low | Open |
| L-02 | `clearBatch` has no minimum batch interval enforcement | Low | Acknowledged |
| I-01 | ERC-1155 callback reentrancy surface on non-internal markets | Informational | Acknowledged |
| I-02 | Sell fee dual `redeemFromPool` pattern is non-obvious | Informational | Documented |

### Detailed Findings

---

#### L-01: `uint16` Cast on `params.length` in Batch Operations

**Severity:** Low
**Contract:** OrderBook.sol
**Functions:** `placeOrders` (L366, L368), `replaceOrders` (L419, L420)

**Description:**

```solidity
require(activeOrderCount[msg.sender][marketId] + uint16(params.length) <= MAX_USER_ORDERS, ...);
activeOrderCount[msg.sender][marketId] += uint16(params.length);
```

`params.length` is `uint256`. The `uint16()` cast silently truncates values > 65535. If `params.length == 65556`, the cast yields `20`, potentially bypassing the `MAX_USER_ORDERS` cap check.

**Impact:** Not exploitable in practice — 65536 `OrderParam` calldata structs would exceed the block gas limit by orders of magnitude. Code quality issue only.

**Recommendation:**

Add an explicit length guard before the cast:

```solidity
require(params.length <= MAX_USER_ORDERS, "OrderBook: batch too large");
```

---

#### L-02: `clearBatch` Has No Minimum Batch Interval Enforcement

**Severity:** Low
**Contract:** BatchAuction.sol
**Function:** `clearBatch` (L98)

**Description:**

`batchInterval` is stored in `Market` but not enforced in `clearBatch`. Any address can call `clearBatch` at any time, enabling MEV sandwich attacks: an attacker can front-run `clearBatch`, place an order, isolate a single user in a nearly empty batch, and match at the user's limit price instead of the fair clearing price.

This is documented in NatSpec (L87–96) as an acknowledged design trade-off between latency and MEV resistance.

**Impact:** MEV extraction surface. Mitigated by price-proximity filtering which parks far-from-price orders in the resting list, making it harder to isolate a user at an extreme tick.

**Recommendation:** Enforce `block.timestamp >= lastClearTimestamp + batchInterval` or restrict `clearBatch` to a permissioned keeper for mainnet deployment.

---

#### I-01: ERC-1155 Callback Reentrancy Surface on Non-Internal Markets

**Severity:** Informational
**Contract:** BatchAuction.sol, OrderBook.sol

**Description:**

Markets using `useInternalPositions = false` transfer ERC-1155 tokens via `safeTransferFrom`, which invokes `onERC1155Received` on the recipient. A malicious receiver could revert in the callback, blocking settlement for the entire batch. `ReentrancyGuard` prevents state corruption but not callback reverts.

**Impact:** DoS on batch settlement for affected markets only. Markets default to `useInternalPositions = true` (created via `createMarketWithPositions`), which avoids ERC-1155 transfers entirely.

**Recommendation:** Use only `useInternalPositions = true` markets for production. If ERC-1155 markets are needed, implement a pull-based claim pattern or a `settlementActive` lock that skips reverting orders.

---

#### I-02: Sell Fee Dual `redeemFromPool` Pattern Is Non-Obvious

**Severity:** Informational
**Contract:** BatchAuction.sol
**Function:** `_settleSellOrder` (L540–L546)

**Description:**

Sell-side settlement makes two `vault.redeemFromPool` calls — one for the seller's payout, one for the sell fee to the protocol collector:

```solidity
vault.redeemFromPool(o.marketId, o.owner, payout);                          // grossPayout - sellFee
vault.redeemFromPool(o.marketId, feeModel.protocolFeeCollector(), sellFee); // sellFee
```

Total withdrawal = `payout + sellFee = grossPayout = filledCollateral` (what the buy side deposited). Pool net delta = 0. Accounting is correct but the two-call pattern requires careful reading to verify solvency.

**Recommendation:** Add a comment block documenting the pool flow for Bid+SellYes and Ask+SellNo match types.

---

## Previous Audit Findings

All findings from the v1.1 audit and the initial v1.2 audit pass (pre-fix) are listed below.

### v1.1 Audit Findings

| ID | Title | Severity | Status | Resolution |
|----|-------|----------|--------|------------|
| v1.1-H-01 | Cross-contract ERC-1155 reentrancy DoS | High | Mitigated | Default `useInternalPositions = true` avoids ERC-1155 transfers. See I-01. |
| v1.1-M-01 | PythResolver `conf == 0` bypass | Medium | Acknowledged | By design — `conf == 0` means no confidence data published; skip check. |
| v1.1-M-02 | Redemption `uint128` truncation | Medium | Acknowledged | `lots` field is `uint64`; `uint128` cast safe for all realistic values. |
| v1.1-M-03 | Chunked settlement re-computes fills (rounding drift) | Medium | **Fixed** | Precomputed fills stored in `_precomputedFills` mapping during first chunk, reused by subsequent chunks. |
| v1.1-L-01 | Unbounded GTC rollover | Low | **Fixed** | Far-from-price GTC orders park in resting list via `_tryRollOrCancel`. `MAX_ORDERS_PER_BATCH` raised to 1600. |
| v1.1-L-02 | Sell orders pay zero fees | Low | **Fixed** | 50/50 fee split: buy side pays `calculateOtherHalfFee`, sell side pays `calculateHalfFee` deducted from payout. |
| v1.1-L-03 | No batch interval enforcement | Low | Acknowledged | Documented in NatSpec. See L-02. |

### Initial v1.2 Audit Findings (Pre-Fix)

| ID | Title | Severity | Status | Resolution |
|----|-------|----------|--------|------------|
| v1.2-M-01 | Resting list unbounded scan — gas griefing | Medium | **Fixed** | `pullRestingOrders` now uses paginated scanning via `restingScanIndex` + `MAX_RESTING_SCAN = 400` bound. Multiple `clearBatch` calls process the full list. |
| v1.2-M-02 | `_tryRollOrCancel` receives stale lots after partial fill | Medium | **Fixed** | `_settleBuyOrder` and `_settleSellOrder` now construct `remaining` OrderInfo with `remaining.lots = o.lots - filledLots` before calling `_tryRollOrCancel`. |
| v1.2-L-01 | Dead `_hasPrecomputed` mapping wastes gas | Low | **Fixed** | `_hasPrecomputed` mapping removed entirely. Only `_precomputedFills` is used. |
| v1.2-L-02 | `uint16` cast on `params.length` | Low | Open | See L-01 above. Not exploitable but remains as code quality issue. |
| v1.2-L-03 | `activeOrderCount` saturating decrement masks bugs | Low | **Fixed** | `decrementActiveOrderCount` now uses `require(activeOrderCount[user][marketId] > 0, ...)`. User-facing cancel paths (`_cancelCore`, `_cancelForReplace`) also use `require`. |
| v1.2-I-01 | `_isTickFar` public with internal naming convention | Informational | **Fixed** | Renamed to `isTickFar`. Internal counterpart `isTickNear` also uses correct convention. |

---

## Invariant Analysis

### 1. `activeOrderCount` Conservation

Every order placement increments the counter; every final removal (cancel, full fill, GTB expiry, GTB zero-fill cleanup) decrements it. GTC partial fills do NOT decrement (order remains active). GTC roll-to-resting does NOT decrement (order stays counted while parked).

| Path | Increment | Decrement | Verified |
|------|-----------|-----------|----------|
| `placeOrder` | +1 | — | Yes |
| `placeOrders` | +`params.length` | — | Yes |
| `replaceOrders` | +`params.length` after cancels | -1 per cancel via `_cancelForReplace` | Yes |
| `cancelOrder` / `cancelOrders` | — | -1 via `_cancelCore` | Yes |
| `cancelExpiredOrder(s)` | — | -1 via `_cancelCore` | Yes |
| Settlement: full fill | — | -1 via `decrementActiveOrderCount` | Yes |
| Settlement: GTB non-participating | — | -1 via `decrementActiveOrderCount` | Yes |
| Settlement: GTB zero-fill cleanup | — | -1 via `decrementActiveOrderCount` | Yes |
| Settlement: GTC partial fill → roll | — | None (order stays active) | Correct |
| Settlement: GTC partial fill → resting | — | None (order stays counted) | Correct |
| `pullRestingOrders` (cancelled entry) | — | None (lazy skip, already decremented at cancel time) | Correct |

`decrementActiveOrderCount` uses `require(> 0)` to catch accounting bugs rather than silently saturating.

### 2. Resting ↔ Tree Consistency

**Invariant:** If `isResting[orderId] == true`, the order's volume is NOT in the segment tree.

| Entry Point | Tree Updated? | `isResting` Set? | Consistent |
|-------------|---------------|------------------|------------|
| `placeOrder` / `_placeOne` → far | Not added to tree | `true` | Yes |
| `placeOrder` / `_placeOne` → near | Added to tree | `false` | Yes |
| `pullRestingOrders` → near | Added to tree | Set to `false` | Yes |
| `_tryRollOrCancel` → far | Removed from tree | `true` (via `pushRestingOrderId`) | Yes |
| `_tryRollOrCancel` → near | Not removed | `false` (stays in tree) | Yes |
| `_cancelCore` → resting order | No tree update | Set to `false` | Yes |
| `_cancelCore` → active order | Removed from tree | N/A | Yes |
| `_cancelForReplace` → resting order | No tree update | Set to `false` | Yes |
| `_cancelForReplace` → active order | Removed from tree | N/A | Yes |

### 3. Pool Solvency with Fee Split

For all match types, pool inflows and outflows balance correctly:

**Bid + Ask match at clearing tick `t`:**
- Pool receives: `lots * t/100 * LOT_SIZE` (from Bid) + `lots * (100-t)/100 * LOT_SIZE` (from Ask) = `lots * LOT_SIZE`
- Each lot-pair is backed by `LOT_SIZE` in the pool
- Fees: buy-side pays `calculateOtherHalfFee` from locked excess to fee collector (not extracted from pool)
- Redemption: winning side redeems `LOT_SIZE` per lot. Pool solvent.

**Bid + SellYes match at clearing tick `t`:**
- Pool receives from buyer: `filledCollateral = lots * t/100 * LOT_SIZE` (via `vault.settleFill`)
- Pool pays seller: `payout = grossPayout - sellFee` (via `vault.redeemFromPool`)
- Pool pays fee collector: `sellFee = calculateHalfFee(grossPayout)` (via `vault.redeemFromPool`)
- Total pool out: `payout + sellFee = grossPayout = filledCollateral`
- Net pool delta from this match: **0**
- Original backing from Bid+Ask match that created the seller's tokens remains intact
- Seller's tokens burned via `burnEscrow`, removing their redemption claim
- Buyer's new YES tokens backed by the original pool deposit. Pool solvent.

**Ask + SellNo match:** Symmetric to Bid + SellYes. Pool solvent.

**Fee invariant:** `calculateHalfFee(x) + calculateOtherHalfFee(x) == calculateFee(x)` for all `x`.
Verified: `ceil(fullFee/2) + floor(fullFee/2) = fullFee`.

### 4. Token Conservation

- **Minting:** `mintSingle` creates one outcome token per filled lot. Only callable by `MINTER_ROLE` (BatchAuction).
- **Burning:** `burnEscrow` destroys sell-order tokens on fill. Only callable by `ESCROW_ROLE` (BatchAuction).
- **Escrow:** OrderBook holds sell-order tokens via `ERC1155Holder`. Returned on cancel/non-fill, burned on fill.
- **Redemption:** Burns winning tokens 1:1 for `LOT_SIZE` USDT from pool.
- **No double-processing:** `o.lots = 0` guard in `_settleOrder` prevents re-settlement. Precomputed fills prevent rounding drift across chunks.

---

## Test Coverage

**347 tests across 17 test suites, all passing.**

**Strengths:**
- Dedicated `AuditFixes.t.sol` (836 lines) covering all v1.2 features
- Per-user cap: placement, cancellation, fill decrement, GTB zero-fill cleanup
- Fee split: equal fees, total preservation, rounding, fuzz solvency checks
- Multi-chunk settlement: 3-chunk scenarios, partial fills across chunks, both-sides GTC
- Proximity filtering: far/near placement, pull-in, cancel resting, GTC roll-to-resting, lazy skip, paginated scan
- Batch operations: `placeOrders`, `replaceOrders` with proximity interactions
- Oracle resolution: Pyth integration, challenge mechanism, finality gate
- Emergency: timelock withdrawal, pool drain

**Coverage Gaps:**

| Gap | Risk | Recommendation |
|-----|------|----------------|
| Malicious `IERC1155Receiver` callback during settlement | Low | Add test with reverting/gas-griefing receiver for non-internal markets |
| Resting list with > `MAX_RESTING_PULL` (200+) entries | Low | Test that paginated scan correctly processes across multiple `clearBatch` calls |
| `replaceOrders` mixing resting + active cancels with new placements | Low | Test `activeOrderCount` correctness for mixed resting/active replace |
| `isTickFar` boundary at exactly `ref ± PROXIMITY_THRESHOLD` | Low | Fuzz test boundary conditions at threshold edges |

---

## Conclusion

The Strike v1.2 codebase is in strong shape after all post-audit fixes have been applied. All Medium and Low findings from the initial v1.2 audit pass are resolved:

- **Paginated resting scan** (`restingScanIndex` + `MAX_RESTING_SCAN`) eliminates the unbounded gas griefing vector
- **Stale lots fix** in `_tryRollOrCancel` ensures GTC partial fills roll the correct remaining quantity
- **Dead code removal** (`_hasPrecomputed`) reduces gas overhead in chunked settlement
- **Reverting `decrementActiveOrderCount`** catches accounting bugs instead of silently absorbing them
- **`isTickFar` rename** aligns naming convention with visibility

**Key strengths:**
- Pool solvency maintained across all match types including Bid+SellYes (verified by accounting traces and fuzz tests)
- Paginated resting list scanning bounds gas consumption per `clearBatch` call
- Chunked settlement with precomputed fills enables arbitrarily large batches
- Per-user order cap (20) limits Sybil griefing surface
- Clear separation of concerns across 10 focused contracts

**Residual risks (all low/acknowledged):**
- ERC-1155 callback DoS affects non-internal markets only (mitigated by default configuration)
- MEV exposure on `clearBatch` timing (mitigated by proximity filtering)
- `params.length` uint16 truncation (not exploitable due to gas limits)

**Mainnet Readiness:** The protocol is ready for mainnet deployment with the following recommendations:
1. Default to `useInternalPositions = true` for all markets (avoids ERC-1155 reentrancy surface)
2. Deploy a permissioned keeper for `clearBatch` to reduce MEV exposure
3. Add the explicit `params.length <= MAX_USER_ORDERS` guard before mainnet (minor hardening)
