# Strike Contracts — Claude Code Context

## Overview

Binary outcome prediction market protocol (v1) on BNB Chain. Users trade YES/NO outcome tokens via a Central Limit Order Book (CLOB) with Frequent Batch Auctions (FBA).

## Key Design Decisions

- **4-sided orderbook:** `Side` enum: `Bid`=0, `Ask`=1, `SellYes`=2, `SellNo`=3. Bid/Ask lock USDT. SellYes/SellNo lock outcome tokens in OrderBook custody (`ERC1155Holder`).
- **placeOrder signature:** `placeOrder(marketId, side, orderType, tick, lots)` — orderType is 3rd param.
- **Batch order functions:** `placeOrders(OrderParam[])` for batch placement, `replaceOrders(cancelIds, OrderParam[])` for atomic cancel+place, `cancelOrders(orderIds)` for batch cancel.
- **Pyth Core (standard pull oracle):** Resolution uses `IPyth.parsePriceFeedUpdates()` from `@pythnetwork/pyth-sdk-solidity`. Price feed IDs are `bytes32`. BSC testnet Pyth: `0xd7308b14BF4008e7C7196eC35610B1427C5702EA`.
- **Order types:** GoodTilCancel (GTC) persists across batches; GoodTilBatch (GTB) expires after one batch.
- **LOT_SIZE = 1e16 ($0.01/lot):** Defined in `ITypes.sol`. All collateral math uses this constant.
- **Segment tree clearing:** 99-tick range (1-99), each tick = 1% probability. Binary search + tick+1 correction for maximum matched volume.
- **Token custody:** OrderBook is `ERC1155Holder`. Sell orders transfer tokens in; cancel/non-fill returns them; fill burns via `burnEscrow`.
- **SellYes payout:** at clearing tick, `lots * clearingTick / 100 * LOT_SIZE` USDT from pool.
- **SellNo payout:** at clearing tick, `lots * (100 - clearingTick) / 100 * LOT_SIZE` USDT from pool.
- **User flow for sell orders:** approve `OutcomeToken.setApprovalForAll(OrderBook, true)` once, then place SellYes/SellNo orders.
- **ESCROW_ROLE:** Role on OutcomeToken, granted to BatchAuction. Used by `burnEscrow()`.
- **USDT collateral:** 1 YES + 1 NO = 1 USDT. Users approve Vault before trading.
- **Atomic clearBatch(marketId):** No orderIds param. Contract reads `batchOrderIds[marketId][batchId]` internally. No separate claim step.
- **Clearing price settlement:** All fills pay the clearing tick, not their limit tick. Excess refund = (locked at order tick) - (cost at clearing tick).
- **Uniform 20bps fee:** No maker/taker. `clearingBountyBps` exists but set to 0.
- **Batch overflow:** MAX_ORDERS_PER_BATCH = 400, spills to next batch when full.
- **Permissioned market creation:** Requires MARKET_CREATOR_ROLE (no creation bond).

## File Structure

- `src/ITypes.sol` — All shared types, enums, structs. `LOT_SIZE` constant lives here.
- `src/SegmentTree.sol` — Pure library, 128-leaf segment tree for O(log n) operations.
- `src/OrderBook.sol` — Order management. OPERATOR_ROLE for BatchAuction/Factory.
- `src/BatchAuction.sol` — Clearing + settlement. Needs OPERATOR_ROLE on OrderBook, PROTOCOL_ROLE on Vault, MINTER_ROLE on OutcomeToken.
- `src/Vault.sol` — USDT custody. PROTOCOL_ROLE for OrderBook/BatchAuction/Redemption.
- `src/MarketFactory.sol` — Market creation. ADMIN_ROLE for PythResolver.
- `src/PythResolver.sol` — Oracle integration. Admin = deployer (not AccessControl).

## BSC Testnet Addresses (v1)

- MockUSDT: `0xb242dc031998b06772C63596Bfce091c80D4c3fA`
- FeeModel: `0xf5b6889a56f9d95c059be028e682f802aee6c074`
- OutcomeToken: `0xc398678d4eb9b5a67dd3b2ff9cd6c517140fcf65`
- Vault: `0x04606a6f4909d0e9d9d763083d7649a2229eb679`
- OrderBook: `0x9675bab261a6f168dd76fedb6d8706021e338c16`
- BatchAuction: `0x62224a55d05175eaeb22fc6263355c820c77e849`
- MarketFactory: `0xf3ad14f117348de4886c29764fdcaf9c62794535`
- PythResolver: `0x5e7b8bb9d18bc620a19cea78caaf51e1ab8afa92`
- Redemption: `0xd181cc898bbbf4d2ddaebf6f245f043dd8f93704`
- Pyth Core: `0xd7308b14BF4008e7C7196eC35610B1427C5702EA`

## How to Run

```bash
forge build
forge test -vv       # 292 tests
```

## Common Gotchas

- **LOT_SIZE** is a file-level constant in `ITypes.sol`, NOT inside a contract. Use `//` comments (not `///`) for file-level declarations to avoid Solidity NatSpec errors.
- **OPERATOR_ROLE grants:** BatchAuction AND MarketFactory both need OPERATOR_ROLE on OrderBook.
- **MINTER_ROLE grants:** BatchAuction AND Redemption both need MINTER_ROLE on OutcomeToken.
- **PROTOCOL_ROLE grants:** OrderBook, BatchAuction, AND Redemption need PROTOCOL_ROLE on Vault.
- **Pyth priceId is bytes32** (stored in `MarketMeta.priceId`). No feed ID mapping needed — PythResolver reads it directly from MarketFactory.
- **Batch interval enforcement:** `clearBatch` enforces minimum time between clears. Tests must `vm.warp()` between consecutive clears.
- **Stack-too-deep:** `claimFills` uses `SettleAmounts` struct to avoid stack overflow. Add structs for multi-variable functions.
- **PythResolver admin:** Set to `msg.sender` in constructor (simple ownership, not AccessControl).
