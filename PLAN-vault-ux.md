# Plan: Direct-from-Wallet Trading UX

**Goal:** Remove the deposit/withdraw step. Users pay BNB directly when placing orders, and receive BNB back directly on cancel/claim/redeem. The Vault becomes internal escrow only — never user-facing.

---

## Current Flow (3+ steps)
```
1. Vault.deposit{value: X}()           → user deposits BNB into vault
2. OrderBook.placeOrder(...)            → locks from vault balance
3. cancel/claimFills                    → unlocks to vault balance
4. Vault.withdraw(amount)              → user pulls BNB out
```

## Target Flow (1 step per action)
```
1. OrderBook.placeOrder{value: collateral}(...)  → BNB goes straight from wallet to vault escrow
2. cancel/claimFills                              → BNB returns directly to wallet
3. Redemption.redeem(...)                         → payout sent to wallet
```

---

## Contract Changes

### 1. Vault
- Becomes purely internal — no public `deposit()` or `withdraw()`
- New functions (callable only by OrderBook/BatchAuction/Redemption):
  - `depositFor{value}(address user)` — credits user balance from msg.value
  - `withdrawTo(address user, uint256 amount)` — sends BNB to user wallet, decrements balance
- Existing `lock()` / `unlock()` / `settleFill()` stay as-is (internal accounting)
- Remove or restrict public `deposit()` and `withdraw()`

### 2. OrderBook.placeOrder
- Make `payable`
- Calculate collateral, require `msg.value == collateral`
- Call `vault.depositFor{value: msg.value}(msg.sender)` then `vault.lock(msg.sender, collateral)`
- Or combine into a single `vault.depositAndLock{value}(msg.sender, collateral)`

### 3. OrderBook.cancelOrder
- After `vault.unlock()`, also call `vault.withdrawTo(msg.sender, collateral)`
- User receives BNB back in the same tx

### 4. BatchAuction.claimFills
- Unfilled collateral: `vault.withdrawTo(owner, unfilledCollateral)` instead of just unlocking
- Filled collateral: still goes to market pool (no change)
- Outcome tokens still minted to user (no change)

### 5. Redemption.redeem
- After burning winning tokens, send BNB payout directly to `msg.sender`
- Currently calls `vault.redeemFromPool()` — ensure this ends with a transfer to user

### 6. BatchAuction.pruneExpiredOrder
- Return collateral to user's wallet, not vault balance

---

## Market Orders (Frontend-Only)

No contract changes needed. The frontend can offer "Market Buy" / "Market Sell" as:
- **Market Buy** = GTB bid at tick 99 (guarantees fill, pays at clearing price)
- **Market Sell** = GTB ask at tick 1 (guarantees fill)
- Frontend shows the current best price as indicative, user clicks buy/sell

---

## Batch Order Placement

With direct-from-wallet, placing multiple orders means multiple `msg.value` transfers. Options:
- `placeMultipleOrders{value: totalCollateral}(Order[] orders)` — batch function
- Can be added later if needed; most users place 1-2 orders at a time

---

## Decisions

1. **Fully direct-from-wallet.** No public deposit/withdraw at all. The Vault has no user-facing functions — it's purely internal escrow between contracts. No optional pre-funding.

2. TBD — more points from Ayaz

---

## Migration / Breaking Changes

- All existing Vault balances would need migration path (or just redeploy since we're pre-mainnet)
- Frontend: remove deposit/withdraw UI, simplify order placement to single tx
- E2e tests: update to use new payable placeOrder pattern
- Infra (indexer): may need to handle new event signatures if Vault events change

---

## Test Plan

- [ ] Place order with exact msg.value — succeeds
- [ ] Place order with wrong msg.value — reverts
- [ ] Place order with 0 msg.value and no vault balance — reverts
- [ ] Cancel order — BNB returned to wallet
- [ ] Claim fills (partial) — unfilled BNB returned, filled stays in pool
- [ ] Claim fills (full) — all collateral to pool, tokens minted
- [ ] Redeem — BNB payout to wallet
- [ ] Prune expired order — BNB returned to wallet
- [ ] Multiple orders in sequence — each takes msg.value independently
