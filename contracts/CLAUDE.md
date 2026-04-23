# Strike Contracts — Claude Code Context

## Overview

Binary outcome prediction market protocol (v1) on BNB Chain. Users trade YES/NO outcome tokens via a Central Limit Order Book (CLOB) with Frequent Batch Auctions (FBA).

## Key Design Decisions

- **4-sided orderbook:** `Side` enum: `Bid`=0, `Ask`=1, `SellYes`=2, `SellNo`=3. Bid/Ask lock USDT. SellYes/SellNo lock outcome tokens in OrderBook custody (`ERC1155Holder`).
- **placeOrder signature:** `placeOrder(marketId, side, orderType, tick, lots)` — orderType is 3rd param.
- **Batch order functions:** `placeOrders(OrderParam[])` for batch placement, `replaceOrders(cancelIds, OrderParam[])` for atomic cancel+place, `cancelOrders(orderIds)` for batch cancel.
- **Pyth Core (standard pull oracle):** Resolution uses `IPyth.parsePriceFeedUpdates()` from `@pythnetwork/pyth-sdk-solidity`. Price feed IDs are `bytes32`. BSC testnet stable Pyth: `0x5744Cbf430D99456a0A8771208b674F27f8EF0Fb`.
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

## BSC Testnet Addresses (current)

- MockUSDT: `0xb242dc031998b06772C63596Bfce091c80D4c3fA`
- FeeModel: `0x5b8fCB458485e5d63c243A1FA4CA45e4e984B1eE`
- OutcomeToken: `0x92dFA493eE92e492Df7EB2A43F87FBcb517313a9`
- Vault: `0xEd56fF9A42F60235625Fa7DDA294AB70698DF25D`
- OrderBook: `0x9CF4544389d235C64F1B42061f3126fF11a28734`
- BatchAuction: `0x8e4885Cb6e0D228d9E4179C8Bd32A94f28A602df`
- MarketFactory: `0xa1EA91E7D404C14439C84b4A95cF51127cE0338B`
- PythResolver: `0x9ddadD15f27f4c7523268CFFeb1A1b04FEEA32b9`
- AIResolver: `0xe2aAec0A169D39FB12b43edacB942190b152439b`
- Redemption: `0x98723a449537AF17Fd7ddE29bd7De8f5a7A1B9B2`
- Pyth Core: `0x5744Cbf430D99456a0A8771208b674F27f8EF0Fb`

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
- **Stale testnet oracle gotcha:** `0xd7308b14BF4008e7C7196eC35610B1427C5702EA` is stale for current Hermes stable updates and caused `InvalidWormholeVaa()` failures during the 2026-04-22 recovery pass.
