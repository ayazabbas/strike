# Sell Orders — V2 Feature Plan

**Goal:** Allow users to sell existing YES/NO outcome tokens back into the market at the
current clearing price, with the same UX as buying. No additional USDT required.

**Why it's safe:** Pool solvency is maintained automatically. When a YES+NO pair is
originally created, both sides contribute full `LOT_SIZE` USDT to the pool. Transferring
existing tokens between parties does not change the pool's outstanding obligations — the
original collateral stays locked. The new buyer's USDT payment flows to the seller, not
to the pool, because the pool was already fully funded.

---

## 1 · Contract Changes (`~/dev/strike/`)

### 1.1 `ITypes.sol` — Add sell sides to `Side` enum

```solidity
enum Side {
    Bid,     // buy YES: lock tick/100 * LOT_SIZE USDT → receive YES tokens at fill
    Ask,     // buy NO:  lock (100-tick)/100 * LOT_SIZE USDT → receive NO tokens at fill
    SellYes, // sell YES tokens: lock YES tokens → receive tick/100 * LOT_SIZE USDT at fill
    SellNo   // sell NO tokens:  lock NO tokens → receive (100-tick)/100 * LOT_SIZE USDT at fill
}
```

`SellYes` orders sit on the ask side of the book (they provide YES to bidders).
`SellNo` orders sit on the bid side of the book (they provide NO to askers).

No changes to `Order` struct. Tick semantics unchanged:
- `SellYes` at tick T = "sell YES for at least T cents per lot"
- `SellNo` at tick T = "sell NO for at least (100-T) cents per lot"

### 1.2 `OrderBook.sol` — `placeOrder`

Add token custody alongside existing USDT locking:

```solidity
function placeOrder(
    uint256 marketId,
    Side side,
    OrderType orderType,
    uint256 tick,
    uint256 lots
) external nonReentrant returns (uint256 orderId) {
    ...
    if (side == Side.SellYes || side == Side.SellNo) {
        // Lock outcome tokens instead of USDT
        bool isYes = (side == Side.SellYes);
        uint256 tokenId = isYes
            ? outcomeToken.yesTokenId(marketId)
            : outcomeToken.noTokenId(marketId);
        outcomeToken.safeTransferFrom(msg.sender, address(this), tokenId, lots, "");
        // No vault.lock() call — no USDT needed
    } else {
        // Existing USDT collateral path (unchanged)
        uint256 collateral = _collateral(lots, tick, side);
        uint256 fee = feeModel.calculateFee(collateral);
        collateralToken.safeTransferFrom(msg.sender, address(vault), collateral + fee);
        vault.lock(msg.sender, collateral + fee);
    }
    ...
}
```

OrderBook holds the tokens in custody. A new mapping tracks token collateral:

```solidity
mapping(uint256 => uint256) public sellOrderTokenLots; // orderId → lots locked
```

### 1.3 `OrderBook.sol` — `cancelOrder` / `cancelOrders`

Add token refund path alongside existing USDT unlock:

```solidity
if (side == Side.SellYes || side == Side.SellNo) {
    bool isYes = (side == Side.SellYes);
    uint256 tokenId = isYes
        ? outcomeToken.yesTokenId(order.marketId)
        : outcomeToken.noTokenId(order.marketId);
    outcomeToken.safeTransferFrom(address(this), order.owner, tokenId, order.lots, "");
} else {
    // existing vault unlock path
}
```

### 1.4 `BatchAuction.sol` — `clearBatch` settlement

Two sell-order cases in settlement (inside the per-order loop):

**Case A — SellYes matched at clearing tick C:**
- Send seller: `filledLots * LOT_SIZE * clearingTick / 100` USDT (from vault pool)
- Transfer YES tokens from OrderBook custody to bidder (instead of minting new YES)
- Bidder gets existing YES tokens → no new minting for YES side of this match

**Case B — SellNo matched at clearing tick C:**
- Send seller: `filledLots * LOT_SIZE * (100 - clearingTick) / 100` USDT
- Transfer NO tokens from OrderBook custody to asker
- Asker gets existing NO tokens → no new minting for NO side of this match

```solidity
if (o.side == Side.SellYes) {
    // Pay seller USDT from pool
    uint256 payout = (s.filledLots * LOT_SIZE * result.clearingTick) / 100;
    vault.redeemFromPool(o.marketId, o.owner, payout);
    // Deliver tokens to matched bidder (handled in bid settlement below)
    // Mark this fill as token-source for the matched bid

} else if (o.side == Side.SellNo) {
    uint256 payout = (s.filledLots * LOT_SIZE * (100 - result.clearingTick)) / 100;
    vault.redeemFromPool(o.marketId, o.owner, payout);
}
```

Pool solvency: the pool already holds `filledLots * LOT_SIZE` per matched pair from
original minting. Paying the seller `C/100 * LOT_SIZE` per lot is identical to the
eventual redemption payout — it draws exactly what the bid-side originally funded.

The matching engine (SegmentTree + clearing tick logic) treats `SellYes` identically to
`Ask` for clearing tick calculation — they both sit on the ask side. `SellNo` sits on
the bid side alongside regular `Bid` orders.

### 1.5 `OutcomeToken.sol`

Add `ESCROW_ROLE` (granted to OrderBook) so the OrderBook can hold and transfer tokens
in custody without being a minter:

```solidity
bytes32 public constant ESCROW_ROLE = keccak256("ESCROW_ROLE");
```

No new mint/burn functions needed — `safeTransferFrom` handles custody.

### 1.6 `Deploy.s.sol`

- Grant `ESCROW_ROLE` on OutcomeToken to OrderBook address
- Grant `MARKET_CREATOR_ROLE` + `ADMIN_ROLE` on MarketFactory to keeper wallet
  (add these lines that are currently missing — the two manual grants currently needed
  after every deploy)

---

## 2 · Tests (`~/dev/strike/contracts/test/`)

### New test file: `SellOrders.t.sol`

All tests should pass alongside existing 245.

```
SellOrders.t.sol
├── test_PlaceSellYesOrder_locksTokens
├── test_PlaceSellNoOrder_locksTokens
├── test_CancelSellYesOrder_returnsTokens
├── test_CancelSellNoOrder_returnsTokens
├── test_ClearBatch_SellYes_vs_Bid
│   └── verify: seller gets USDT, bidder gets existing YES tokens (no new mint)
├── test_ClearBatch_SellNo_vs_Ask
│   └── verify: seller gets USDT, asker gets existing NO tokens (no new mint)
├── test_ClearBatch_Mixed_RegularAndSell
│   └── sell YES + regular ask both on offer side; clears correctly
├── test_ClearBatch_SellYes_PoolSolvency
│   └── full lifecycle: buy pair → sell YES → market resolves → NO holder redeems full LOT_SIZE
├── test_ClearBatch_SellYes_PriceBelowClearing_NotFilled
│   └── sell YES at tick 40 when clearing at 30 → order not filled
├── test_ClearBatch_SellYes_GTC_Rollover
│   └── GTC sell order survives multiple batches until filled
├── test_SellYes_PartialFill
├── test_SellYes_RevertOnInsufficientTokenBalance
├── test_SellYes_RevertOnExpiredMarket
└── test_SellNo_PoolSolvency
    └── full lifecycle: buy pair → sell NO → market resolves → YES holder redeems full LOT_SIZE
```

Update existing tests:
- `BatchAuction.t.sol`: verify existing tests still pass with new `Side` enum values
- `OrderBook.t.sol`: add coverage for the new `placeOrder` paths

---

## 3 · Infra Changes (`~/dev/strike-infra/`)

### 3.1 ABIs (`crates/strike-common/abi/`)

- `OrderBook.json` — updated `placeOrder` (new `Side` enum values 2 and 3)
- `BatchAuction.json` — updated `OrderSettled` event (no signature change needed if
  sell payouts are emitted as `collateralReleased`; otherwise add `isSell` field)
- `OutcomeToken.json` — no change

### 3.2 Indexer (`services/indexer/src/`)

**`indexer.rs` — `OrderPlaced` handler:**
- Detect `SellYes`/`SellNo` sides and store `is_sell = true` in DB

**`indexer.rs` — `OrderSettled` handler:**
- For sell orders: `filled_lots` = lots transferred; `collateral_released` = USDT received
- No `outcome_tokens_minted` (already 0 and will stay 0 for sell orders)

**`indexer.rs` — `BatchCleared` broadcast:**
- No change needed (clearing tick and matched lots apply to mixed regular+sell batches)

### 3.3 DB schema (`crates/strike-db/`)

Add to `orders` table:

```sql
ALTER TABLE orders ADD COLUMN is_sell BOOLEAN NOT NULL DEFAULT FALSE;
```

New migration file: `migrations/XXXX_add_sell_order_flag.sql`

### 3.4 API (`services/indexer/src/api.rs`)

`/positions/{address}` response:
- Add `"is_sell": true` flag to filled sell orders so the frontend can display them
  differently ("Sold YES @ 67c" rather than "Bought NO @ 33c")

---

## 4 · MM Changes (`~/dev/strike-mm/`)

No functional changes required — MM never uses sell orders (it mints fresh pairs).

Update:
- Config addresses after redeploy
- ABI files if signatures change

---

## 5 · Frontend Changes (`~/dev/strike-frontend/`)

### 5.1 `src/components/order/OrderForm.tsx`

**Enable Sell tab:**
```tsx
// Remove `disabled` from Sell button
// When sell tab active: show token balance (YES or NO) instead of USDT balance
// Max amount = token balance, not USDT balance
// Submit calls placeOrder with Side.SellYes (2) or Side.SellNo (3)
```

**Token balance display:**
- New `useTokenBalance(marketId, address, side)` hook
- Calls `OutcomeToken.balanceOf(address, tokenId)` via `useReadContract`
- Shows "Available: X YES" or "Available: X NO" beneath the amount input

**Approval flow:**
- `placeOrder` for sell requires `OutcomeToken.setApprovalForAll(orderBook, true)`
- Replace USDT approval check with `isApprovedForAll` check for sell orders
- One-time per-wallet approval (ERC1155 approval is global)

**Amount input:**
- Sell mode: lots-based input (not USDT-based) since you're selling tokens
- Show estimated USDT proceeds: `lots × LOT_SIZE × tick / 100`

**Market order sell:**
- Sell YES market order tick: `bids[0].price` with slight downward slippage
  (you're willing to sell for slightly less than the best bid to guarantee fill)
- Sell NO market order tick: `(100 - asks[0].price)` equivalent

### 5.2 `src/lib/contracts.ts`

- Update OrderBook ABI to include new `Side` enum values
- Keep other addresses unchanged if only OrderBook+BatchAuction are redeployed

### 5.3 `src/components/market/MyTradesTable.tsx`

Show sell trades with distinct label:
- `is_sell: true` + `side: 'bid'` → "Sold YES"
- `is_sell: true` + `side: 'ask'` → "Sold NO"
- Existing buy fills unchanged

### 5.4 `src/lib/i18n/translations.ts`

New keys:
```
'order.sell'         → already exists (was disabled)
'order.sellYes'      → 'Sell YES' / '卖出YES'
'order.sellNo'       → 'Sell NO' / '卖出NO'
'order.available'    → 'Available' / '可用'
'order.proceeds'     → 'Est. proceeds' / '预计收益'
```

---

## 6 · Documentation

### `~/dev/strike/CLAUDE.md`
- Document `SellYes` / `SellNo` Side enum values
- Document pool solvency guarantee for sell orders

### `~/dev/strike-infra/CLAUDE.md`
- Document `is_sell` column in orders table
- Document `/positions` API `is_sell` field

### `~/dev/strike-website/` (docs.strike.pm)
- New page: "How selling works"
  - Diagram: sell YES → clearing → USDT received
  - Note: one-time OutcomeToken approval required
  - FAQ: "Why do I need to approve before selling?"

---

## 7 · Deploy Checklist

Run in order. Do not skip steps.

### 7.1 Build and test contracts

```bash
cd ~/dev/strike/contracts
forge build
forge test           # must be 245 + new sell-order tests, all green
forge test --gas-report
```

### 7.2 Deploy to BSC testnet

```bash
forge script script/Deploy.s.sol \
  --rpc-url $BSC_TESTNET_RPC \
  --private-key $DEPLOYER_KEY \
  --broadcast \
  --verify
```

Capture new addresses from output. The following contracts change:
| Contract | Changes |
|---|---|
| OrderBook | sell order logic, ESCROW_ROLE |
| BatchAuction | sell settlement in clearBatch |
| OutcomeToken | ESCROW_ROLE added |
| MarketFactory | new OrderBook address wired in |

These contracts are UNCHANGED (redeploy only if ABI changed):
| Contract | Status |
|---|---|
| Vault | unchanged |
| Redemption | unchanged |
| FeeModel | unchanged |
| MockUSDT | unchanged |
| PythResolver | unchanged |

### 7.3 Update the 13 address files

All must be updated before restarting any service.

```
~/dev/strike-infra/.env.testnet
~/dev/strike-infra/crates/strike-common/abi/OrderBook.json
~/dev/strike-infra/crates/strike-common/abi/BatchAuction.json
~/dev/strike-infra/crates/strike-common/abi/OutcomeToken.json
~/dev/strike-mm/config/default.toml
~/dev/strike-mm/abi/OrderBook.json
~/dev/strike-mm/abi/OutcomeToken.json       ← new (needed for approval check)
~/dev/strike-frontend/src/lib/contracts.ts
~/dev/strike-frontend/src/lib/abi/OrderBook.json
~/dev/strike-frontend/src/lib/abi/OutcomeToken.json
~/dev/strike-website/src/lib/contracts.ts   (if exists)
```

### 7.4 DB migration

```bash
# Run migration (adds is_sell column)
# indexer runs migrations on startup — just restart it after updating .env.testnet

# Wipe stale market data from old contract addresses
docker exec strike-infra-postgres-1 psql -U strike -d strike -c "
  TRUNCATE orders, fills, batches, markets, raw_events RESTART IDENTITY CASCADE;"
```

### 7.5 Update INDEXER_FROM_BLOCK

In `.env.testnet`, set `INDEXER_FROM_BLOCK` to the block number of the Deploy tx.
Get it from the BSCScan link printed by `forge script --broadcast`.

### 7.6 Rebuild infra

```bash
cd ~/dev/strike-infra
cargo build --release
```

### 7.7 Restart services (in order)

```bash
sudo systemctl restart strike-indexer
sleep 5
sudo systemctl restart strike-keeper
sleep 5
sudo systemctl restart strike-mm
```

Verify each starts cleanly:
```bash
journalctl -u strike-indexer -f &
journalctl -u strike-keeper -f &
journalctl -u strike-mm -f &
```

### 7.8 Rebuild and restart frontend

```bash
cd ~/dev/strike-frontend
npm run build
sudo systemctl restart strike-frontend
```

### 7.9 Smoke test

1. Faucet: mint test USDT
2. Buy YES on a market → confirm YES token balance appears in OrderForm sell tab
3. Approve OutcomeToken for OrderBook (one-time)
4. Place Sell YES market order → confirm USDT received after next batch
5. Buy NO on a market → sell NO → confirm USDT received
6. Cancel a sell order → confirm tokens returned
7. Let a market resolve → confirm redemption still works for non-sold tokens

---

## 8 · Effort Estimate

| Component | Est. time |
|---|---|
| Contract changes + tests | 2–3 days |
| Infra (ABI + indexer + DB) | 0.5 day |
| Frontend (sell flow + approvals) | 1–2 days |
| Docs + deploy | 0.5 day |
| **Total** | **~1 week** |

---

## 9 · Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Pool underpayment if sell payout > original bid contribution | Pool draws `C/100 × LOT_SIZE` per lot — identical to what bid locked. Mathematically bounded. |
| SegmentTree counts SellYes as Ask (correct) — verify edge case where all offer-side volume is SellYes with no regular Asks | Add explicit test for this scenario. |
| GTC sell orders rolling over batches while price moves against seller | Same GTC cap logic applies. Seller can cancel at any time to get tokens back. |
| ERC1155 approval UX friction (one extra tx before first sell) | Detect `isApprovedForAll` on page load. Show one-time approve prompt inline before first sell. |
| Partial fills on sell orders leave some tokens locked | Already handled by cancel/GTC rollover logic — same as regular orders. |
