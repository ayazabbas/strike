# Strike V2 Smart Contract Security Audit Report

**Date:** 2026-03-12
**Auditor:** Claude Opus 4.6 (AI-assisted audit)
**Scope:** All Solidity contracts in `contracts/src/`
**Commit:** `5350a15` (master)
**Chain:** BNB Chain (BSC)
**Collateral:** USDT (ERC-20)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Critical Findings](#critical-findings)
3. [High Findings](#high-findings)
4. [Medium Findings](#medium-findings)
5. [Low Findings](#low-findings)
6. [Informational Findings](#informational-findings)
7. [Good Practices Observed](#good-practices-observed)

---

## Executive Summary

The Strike V2 protocol implements a binary outcome prediction market with Frequent Batch Auctions on BNB Chain. The audit identified **2 critical**, **3 high**, **4 medium**, and **3 low** severity issues, plus informational observations.

The most severe finding is a **pool insolvency bug** where protocol fees are deducted from collateral before it enters the redemption pool, but redemption pays out the full LOT_SIZE per token. This guarantees the pool will be underfunded and the last redeemers will be unable to withdraw.

| Severity | Count |
|----------|-------|
| Critical | 2 |
| High | 3 |
| Medium | 4 |
| Low | 3 |
| Informational | 4 |

---

## Critical Findings

### C-01: Market Pool Insolvency — Fees Deducted Before Pool Deposit

**Severity:** Critical
**Location:** `BatchAuction.sol:_settleAmounts()` (lines 172-186)
**Status:** Open

**Description:**

When a batch is cleared, both sides of each matched lot contribute collateral to the market pool. However, protocol fees are subtracted from the collateral *before* it enters the pool:

```solidity
s.protocolFee = feeModel.calculateFee(s.filledCollateral);  // line 184
s.toPool = s.filledCollateral - s.protocolFee;                // line 185
```

At redemption, each winning outcome token redeems for the full `LOT_SIZE` (1 USDT):

```solidity
// Redemption.sol:75
uint256 payout = amount * LOT_SIZE;
```

**Impact:**

For each matched lot, the pool receives:

- Bid side deposits: `LOT_SIZE * clearingTick / 100 * (1 - feeBps/10000)`
- Ask side deposits: `LOT_SIZE * (100 - clearingTick) / 100 * (1 - feeBps/10000)`
- **Total to pool:** `LOT_SIZE * (1 - 20/10000) = LOT_SIZE * 0.998`

But redemption requires `LOT_SIZE` per winning token. The pool is **short by exactly the total fees collected** (0.2% at 20 bps).

For example, a market with 1,000 matched lots at any clearing price:
- Pool receives: `1000 * 1e18 * 0.998 = 998e18 USDT`
- Redemption requires: `1000 * 1e18 = 1000e18 USDT`
- **Deficit: 2e18 USDT (2 USDT)** — the last redeemers cannot withdraw

This is not an attack — it occurs during **normal protocol operation** on every single market. The deficit scales linearly with volume.

**Proof of Concept:**

1. Market created with any strike price
2. 100 users place bids, 100 users place asks
3. clearBatch matches 500 lots at tick 50
4. Bid side pool contribution per lot: `1e18 * 50/100 * 9980/10000 = 4.99e15`
5. Ask side pool contribution per lot: `1e18 * 50/100 * 9980/10000 = 4.99e15`
6. Total per lot: `9.98e15` (vs `1e16` needed)
7. Market resolves, first 499 users redeem successfully
8. Last user's `vault.redeemFromPool()` reverts with "insufficient market pool"

**Recommendation:**

Fees should be charged *on top of* the pool contribution, not deducted from it. Either:

**(a) Charge fees separately (preferred):** Lock `collateral + fee` from the user. Send `collateral` to pool, `fee` to collector. This requires changing the collateral calculation in `placeOrder` to include the fee.

**(b) Fund the pool at full LOT_SIZE:** Change `_settleAmounts` so that `toPool = filledCollateral` (full amount at clearing price) and deduct fees from the excess refund or from a separate fee escrow.

**(c) Reduce redemption payout:** Pay `LOT_SIZE * (1 - feeBps/10000)` per token at redemption. Simpler but changes the token economics.

---

### C-02: Admin Can Resolve Markets With Arbitrary Outcomes (Rug Vector)

**Severity:** Critical
**Location:** `MarketFactory.sol:setResolved()` (lines 177-194)
**Status:** Open

**Description:**

The `setResolved()` function accepts any `ADMIN_ROLE` caller and allows setting any outcome and settlement price, bypassing the oracle entirely:

```solidity
function setResolved(uint256 factoryMarketId, bool outcomeYes, int64 settlementPrice)
    external
    onlyRole(ADMIN_ROLE)
{
    MarketMeta storage meta = marketMeta[factoryMarketId];
    require(
        meta.state == MarketState.Closed || meta.state == MarketState.Resolving,
        "MarketFactory: not closable"
    );
    meta.state = MarketState.Resolved;
    meta.outcomeYes = outcomeYes;
    meta.settlementPrice = settlementPrice;
    // ...
}
```

While `PythResolver` is the intended caller, any address with `ADMIN_ROLE` can call this directly. Additionally, `setResolved` accepts markets in `Closed` state, completely skipping the `Resolving` phase and the oracle.

**Impact:**

A compromised or malicious admin can:
1. Wait for a market to close (or call `closeMarket` themselves since it's permissionless after expiry)
2. Call `setResolved(marketId, false, 0)` to force any outcome
3. Redeem their own winning tokens at the expense of other users

This is a full rug pull capability with no timelock or multi-sig requirement.

**Proof of Concept:**

1. Admin places large ASK orders in a market (buying NO tokens)
2. Market expires and is closed
3. Admin calls `setResolved(marketId, false, 0)` — NO wins, skipping oracle
4. Admin redeems NO tokens for USDT, draining the pool

**Recommendation:**

1. Remove `MarketState.Closed` from the accepted states in `setResolved` — require the market to be in `Resolving` state (which only PythResolver can trigger)
2. Better: Replace `ADMIN_ROLE` access on `setResolved` with a dedicated `RESOLVER_ROLE` that is only granted to `PythResolver`
3. Add a timelock to `setResolved` (e.g., 24h delay) to allow users to exit before resolution takes effect
4. Consider requiring multi-sig for admin actions

---

## High Findings

### H-01: GTC Rollover Can Exceed MAX_ORDERS_PER_BATCH — Gas DoS

**Severity:** High
**Location:** `OrderBook.sol:pushBatchOrderId()` (line 231), `BatchAuction.sol:_settleOrder()` (lines 215, 227, 254)
**Status:** Open

**Description:**

When GTC orders are not filled, they are rolled to the next batch via `pushBatchOrderId()`. This function has no check against `MAX_ORDERS_PER_BATCH`:

```solidity
function pushBatchOrderId(uint256 marketId, uint256 batchId, uint256 orderId)
    external onlyRole(OPERATOR_ROLE)
{
    batchOrderIds[marketId][batchId].push(orderId);  // No max check!
}
```

Meanwhile, `placeOrder` enforces `MAX_ORDERS_PER_BATCH = 400` for new orders, but rolled-over orders bypass this check.

**Impact:**

A batch could accumulate far more than 400 orders through GTC rollover:
1. Batch N: 400 GTC orders placed, most don't fill, 380 roll to N+1
2. Batch N+1: 400 new orders placed + 380 rolled = 780 orders
3. Batch N+2: Could have 400 + 700+ rolled = 1100+ orders

With 1000+ orders, `clearBatch` must iterate over all of them, each making multiple external calls (reduceOrderLots, updateTreeVolume, settleFill, mintSingle). This can easily exceed the BSC block gas limit (140M), making the batch permanently unclearchable.

**Stuck funds:** All orders in the unclearchable batch have locked collateral that cannot be recovered (users can cancel individual orders, but the batch itself remains stuck with phantom volume in the segment tree).

**Proof of Concept:**

1. Attacker places 400 GTC orders at tick 1 (minimum collateral) in market M
2. Keeper clears batch — no asks, so no fills. All 400 roll to next batch
3. Attacker places 400 more orders. Next batch now has 800 orders
4. Repeat until clearBatch exceeds gas limit
5. Market becomes unclearchable. Legitimate orders are stuck

**Recommendation:**

- Enforce `MAX_ORDERS_PER_BATCH` in `pushBatchOrderId`
- If the next batch is full, roll to batch N+2, N+3, etc.
- Alternatively, limit GTC rollover count per order (e.g., max 5 rollovers before auto-cancel)

---

### H-02: Short Finality Window May Prevent Effective Challenges

**Severity:** High
**Location:** `PythResolver.sol` (lines 12, 212)
**Status:** Open

**Description:**

The finality window is `FINALITY_BLOCKS = 3`. On BSC with ~3-second block times, this gives challengers approximately **9 seconds** to:

1. Observe the resolution submission on-chain
2. Obtain an earlier Pyth price update from Hermes API
3. Submit a challenge transaction that gets mined within 3 blocks

```solidity
require(block.number < pending.resolvedAtBlock + FINALITY_BLOCKS, "PythResolver: finality passed");
```

**Impact:**

9 seconds is insufficient for most users to detect and respond to a malicious or incorrect resolution. An attacker could submit a resolution with a cherry-picked price (within the valid time window) that benefits their position, and honest challengers may not be able to respond in time.

**Recommendation:**

- Increase `FINALITY_BLOCKS` to at least 100 (~5 minutes on BSC) to allow realistic challenge response times
- Consider a time-based finality window instead of block-based (e.g., `block.timestamp >= resolvedAtTimestamp + 5 minutes`)

---

### H-03: Pro-Rata Rounding Causes Phantom Volume and Unfair Fills

**Severity:** High
**Location:** `BatchAuction.sol:_calcFilledLots()` (lines 274-280)
**Status:** Open

**Description:**

Pro-rata fill calculation uses integer division which rounds down:

```solidity
function _calcFilledLots(uint256 lots, Side side, BatchResult memory result) internal pure returns (uint256) {
    uint256 totalSideLots = side == Side.Bid ? result.totalBidLots : result.totalAskLots;
    if (totalSideLots <= result.matchedLots) {
        return lots;
    }
    return (lots * result.matchedLots) / totalSideLots;  // rounds down
}
```

When `totalSideLots > matchedLots`, the sum of all individual `filledLots` across orders can be **less than** `matchedLots`. This creates several issues:

1. **Phantom volume:** The segment tree is updated by `filledLots` per order, but the total reduction may be less than `matchedLots`. The residual volume remains in the tree permanently, inflating cumulative volumes and potentially affecting future clearing prices.

2. **Unfair rounding:** Small orders (e.g., 1 lot) when `totalSideLots` is large get rounded to 0 fill. They participate in the auction (their tick crosses) but receive nothing. For GTB orders, this means they lock collateral for a batch and get nothing back (though the collateral is returned for 0-fill orders).

3. **Asymmetric fills:** More YES tokens than NO tokens (or vice versa) could be minted per clearing, since rounding affects each side independently. This causes a mismatch between YES and NO token supply.

**Impact:**

Over many batches, phantom volume accumulates in the segment tree, distorting the clearing price calculation. Small traders get systematically disadvantaged by rounding.

**Recommendation:**

- Track `totalFilledBid` and `totalFilledAsk` during settlement and assign the rounding remainder to the last order in the batch
- Or use a priority queue (e.g., time priority) to assign fills to specific orders rather than pro-rata, eliminating rounding issues

---

## Medium Findings

### M-01: Emergency Mode Does Not Recover Market Pool Funds

**Severity:** Medium
**Location:** `Vault.sol:emergencyWithdraw()` (lines 172-181)
**Status:** Open

**Description:**

In emergency mode, users can withdraw their `balance[msg.sender]`. However, funds in `marketPool[marketId]` are not accessible through any emergency mechanism:

```solidity
function emergencyWithdraw() external nonReentrant {
    // ...
    uint256 total = balance[msg.sender];  // Only user balance, not pool
    balance[msg.sender] = 0;
    locked[msg.sender] = 0;
    collateralToken.safeTransfer(msg.sender, total);
}
```

Once collateral enters the market pool (via `settleFill → addToMarketPool`), it can only leave through `redeemFromPool`, which requires `PROTOCOL_ROLE` (i.e., the Redemption contract). If the Redemption contract is broken or the market is never resolved, these funds are permanently stuck.

**Impact:**

In an emergency scenario (e.g., oracle failure, critical bug), funds in market pools cannot be recovered by users. With active markets, this could represent a significant portion of total protocol TVL.

**Recommendation:**

Add an admin function to drain market pools in emergency mode, or allow `emergencyWithdraw` to also return a pro-rata share of the relevant market pools. Alternatively, add an `emergencyRedeemFromPool` function with timelock protection.

---

### M-02: Missing Reentrancy Guard on BatchAuction.clearBatch

**Severity:** Medium
**Location:** `BatchAuction.sol:clearBatch()` (line 72)
**Status:** Open

**Description:**

`clearBatch` makes multiple external calls in a loop (to Vault, OrderBook, OutcomeToken) but has no `nonReentrant` modifier:

```solidity
function clearBatch(uint256 marketId) external returns (BatchResult memory result) {
    // No nonReentrant modifier
    // ...
    for (uint256 i = 0; i < ids.length; i++) {
        _settleOrder(ids[i], result);  // External calls inside
    }
}
```

While standard USDT does not have transfer hooks, BSC has had non-standard token implementations. Additionally, `OutcomeToken` is ERC-1155 which *does* have receiver hooks (`onERC1155Received`).

**Impact:**

If a malicious contract receives ERC-1155 tokens via `mintSingle` and re-enters `clearBatch`, it could potentially re-process the same batch. The `batchResults` mapping would be overwritten, and the batch advance already happened, so orders would be read from the (already-advanced) batch ID. In practice, the re-entrant call would likely fail or process a different batch, but the state could be corrupted.

**Recommendation:**

Add `nonReentrant` to `clearBatch`. Also consider adding `nonReentrant` to `Vault.settleFill()` which also lacks it.

---

### M-03: confThresholdBps = 0 Blocks All Oracle Resolutions

**Severity:** Medium
**Location:** `PythResolver.sol:_checkConfidence()` (lines 254-259), `setConfThreshold()` (lines 99-102)
**Status:** Open

**Description:**

The admin can set `confThresholdBps` to 0:

```solidity
function setConfThreshold(uint256 newBps) external onlyAdmin {
    require(newBps <= 10000, "PythResolver: bps exceeds 10000");  // Allows 0
    confThresholdBps = newBps;
}
```

When `confThresholdBps = 0`, `_checkConfidence` computes `maxConf = 0`, causing all prices with non-zero confidence to be rejected. Since Pyth always provides confidence intervals, this effectively blocks all market resolutions.

**Impact:**

A malicious or compromised admin can prevent any market from being resolved by setting `confThresholdBps = 0`. Markets would eventually be cancelled (after 24h), and users could cancel orders, but any collateral in the market pool would be stuck (see M-01).

**Recommendation:**

Add a minimum threshold: `require(newBps >= 10, "PythResolver: threshold too low")`.

---

### M-04: Challenge Resets Finality Block — Potential Delay of Resolution

**Severity:** Medium
**Location:** `PythResolver.sol:_applyResolution()` (line 221)
**Status:** Open

**Description:**

Each successful challenge resets the finality timer:

```solidity
pending.resolvedAtBlock = block.number;  // line 221 — resets on every challenge
```

While the `publishTime < pending.publishTime` requirement bounds the number of possible challenges (challenger must provide an *earlier* valid price), the time window is `[expiryTime, expiryTime + 300s]`. An attacker could submit multiple challenges with decreasingly earlier timestamps, each resetting the finality and delaying resolution.

**Impact:**

An attacker could delay resolution by up to ~5 minutes of Pyth publish time granularity multiplied by the number of valid earlier prices available. During this delay, market participants cannot redeem tokens, creating uncertainty and potential panic.

**Recommendation:**

Don't reset `resolvedAtBlock` on challenge. Instead, use the original finality deadline. If a challenge succeeds during the finality window, update the price but keep the original deadline. This ensures resolution completes in bounded time.

---

## Low Findings

### L-01: Negative Price Overflow in _checkConfidence

**Severity:** Low
**Location:** `PythResolver.sol:_checkConfidence()` (line 256)
**Status:** Open

**Description:**

```solidity
uint256 absPrice = price >= 0 ? uint256(uint64(price)) : uint256(uint64(-price));
```

If `price == type(int64).min` (-9223372036854775808), then `-price` overflows `int64` in Solidity 0.8+ and reverts. This would prevent resolution of markets tracking assets with extreme negative prices.

**Impact:** Very low — asset prices in prediction markets are almost always positive. Only relevant for exotic derivatives.

**Recommendation:** Use a safe absolute value: `uint256 absPrice = price >= 0 ? uint256(int256(price)) : uint256(int256(-int256(price)));`

---

### L-02: Cancelled Orders Leave Stale Entries in batchOrderIds

**Severity:** Low
**Location:** `OrderBook.sol:cancelOrder()` (lines 190-219)
**Status:** Open

**Description:**

When an order is cancelled, its entry in `batchOrderIds[marketId][batchId]` is not removed. When `clearBatch` processes that batch, `_settleOrder` reads the order, sees `lots == 0`, and returns early (line 193). This wastes gas iterating over cancelled entries.

**Impact:** Minor gas waste. With many cancellations, `clearBatch` gas cost increases without doing useful work. In extreme cases (hundreds of cancellations in a single batch), this could contribute to gas limit issues.

**Recommendation:** Consider lazy deletion (swap with last element and pop), or accept the gas cost as-is since the impact is minor.

---

### L-03: No Minimum Duration Validation for Short-Lived Markets

**Severity:** Low
**Location:** `MarketFactory.sol:createMarket()` (lines 105-144)
**Status:** Open

**Description:**

The only duration validation is `duration > interval`. With `defaultBatchInterval = 60`, a market can be created with `duration = 61` seconds. Such a short-lived market may not have enough time for meaningful price discovery.

Additionally, if a very short market is created and no one places orders before expiry, the market creates dead state in OrderBook (market struct, batch tracking) that will persist forever.

**Impact:** Low — permissioned market creation mitigates abuse, but a careless MARKET_CREATOR could create useless markets.

**Recommendation:** Add a minimum duration (e.g., 10 minutes): `require(duration >= 600, "MarketFactory: duration too short")`.

---

## Informational Findings

### I-01: USDT Non-Standard Return Value Handled Correctly

SafeERC20 is used consistently for all USDT transfers, properly handling USDT's non-standard `transfer` and `transferFrom` which don't return a boolean on some chains. This is correct.

### I-02: No Event for GTC Order Rollover

When a GTC order is rolled to the next batch (via `pushBatchOrderId`), no event is emitted. This makes it difficult to track order lifecycle off-chain. Consider emitting an `OrderRolledOver(orderId, fromBatchId, toBatchId)` event.

### I-03: clearBatch Is Permissionless

Anyone can call `clearBatch`, which is intentional for a keeper-based architecture. However, this means an attacker could front-run the intended keeper's transaction to clear a batch at a strategically chosen time (e.g., right after their own order is placed). On BSC with 3-second blocks, front-running is feasible but the impact is limited since the batch collects orders over time and the clearing price is deterministic based on the order book state.

### I-04: Struct Packing in ITypes.sol Duplicates contracts/CLAUDE.md Comment

The ITypes.sol file has a comment noting structs were optimized "was 7 slots" → packed. The contracts/CLAUDE.md still references `LOT_SIZE = 1e15 wei (0.001 BNB)` which is outdated — the V2 uses `LOT_SIZE = 1e18` with USDT collateral. This documentation inconsistency in `contracts/CLAUDE.md` could cause confusion.

---

## Good Practices Observed

1. **SafeERC20 usage:** All USDT interactions use OpenZeppelin's SafeERC20, correctly handling non-standard ERC-20 return values.

2. **Efficient struct packing:** `Order`, `BatchResult`, and `Market` structs are tightly packed to minimize storage slots (2, 2, and 1 slots respectively), saving significant gas.

3. **Segment tree for O(log n) clearing:** Using a 128-leaf segment tree for clearing price discovery is efficient and avoids O(n) iteration over ticks.

4. **Emergency withdrawal with timelock:** The 7-day timelock on emergency withdrawals prevents admin from instantly draining funds, giving users time to react.

5. **Two-step admin transfer in PythResolver:** The `setPendingAdmin`/`acceptAdmin` pattern prevents accidental admin loss from typos.

6. **Permissionless market closing and cancellation:** `closeMarket` and `cancelMarket` are callable by anyone when conditions are met (expiry passed, 24h timeout), ensuring markets don't get stuck in limbo.

7. **Batch overflow handling:** The overflow to next batch when `MAX_ORDERS_PER_BATCH` is reached prevents order rejection during busy periods.

8. **Role separation:** Clear role separation between `ADMIN_ROLE`, `OPERATOR_ROLE`, `PROTOCOL_ROLE`, `MINTER_ROLE`, and `MARKET_CREATOR_ROLE` follows the principle of least privilege.

9. **AccessControl over Ownable:** Using OpenZeppelin's AccessControl instead of Ownable provides more granular permission management and supports multi-party admin.

10. **Clearing price settlement:** Settling at the uniform clearing price rather than individual limit prices is fair and prevents price discrimination between orders in the same batch.

---

## Summary of Recommendations (Priority Order)

| Priority | Finding | Fix |
|----------|---------|-----|
| **Immediate** | C-01: Pool insolvency | Restructure fee collection to not deduct from pool |
| **Immediate** | C-02: Admin rug vector | Restrict `setResolved` to RESOLVER_ROLE, require Resolving state |
| **Before Mainnet** | H-01: GTC rollover DoS | Enforce MAX_ORDERS_PER_BATCH in pushBatchOrderId |
| **Before Mainnet** | H-02: Short finality | Increase FINALITY_BLOCKS to 100+ |
| **Before Mainnet** | H-03: Rounding phantom volume | Track and assign rounding remainders |
| **Before Mainnet** | M-01: Emergency pool recovery | Add admin pool drain in emergency |
| **Before Mainnet** | M-02: Missing reentrancy guard | Add nonReentrant to clearBatch |
| **Before Mainnet** | M-03: confThreshold=0 DoS | Add minimum threshold |
| **Recommended** | M-04: Challenge delay | Don't reset finality on challenge |
| **Nice to have** | L-01 through L-03 | Minor fixes as described |

---

*This audit was performed by an AI system and should be supplemented with manual review by experienced smart contract auditors before mainnet deployment. The findings above are based on code review only — no formal verification, fuzzing, or on-chain testing was performed.*
