# Strike Contracts — Claude Code Context

## Overview

Binary outcome prediction market protocol on BNB Chain. Users trade YES/NO outcome tokens via a Central Limit Order Book (CLOB) with Frequent Batch Auctions (FBA).

## Key Design Decisions

- **4-sided orderbook (V7):** `Side` enum: `Bid`=0, `Ask`=1, `SellYes`=2, `SellNo`=3. Bid/Ask lock USDT. SellYes/SellNo lock outcome tokens in OrderBook custody (`ERC1155Holder`).
- **placeOrder signature (V7):** `placeOrder(marketId, side, orderType, tick, lots)` — orderType is 3rd param.
- **Pyth Core (standard pull oracle):** Resolution uses `IPyth.parsePriceFeedUpdates()` from `@pythnetwork/pyth-sdk-solidity`. Price feed IDs are `bytes32`. BSC testnet Pyth: `0xd7308b14BF4008e7C7196eC35610B1427C5702EA`.
- **Order types:** GoodTilCancel (GTC) persists across batches; GoodTilBatch (GTB) expires after one batch.
- **LOT_SIZE = 1e15 wei (0.001 BNB):** Defined in `ITypes.sol`. All collateral math uses this constant.
- **Segment tree clearing:** 99-tick range (1-99), each tick = 1% probability. Binary search + tick+1 correction for maximum matched volume.

## File Structure

- `src/ITypes.sol` — All shared types, enums, structs. `LOT_SIZE` constant lives here.
- `src/SegmentTree.sol` — Pure library, 128-leaf segment tree for O(log n) operations.
- `src/OrderBook.sol` — Order management. OPERATOR_ROLE for BatchAuction/Factory.
- `src/BatchAuction.sol` — Clearing + settlement. Needs OPERATOR_ROLE on OrderBook, PROTOCOL_ROLE on Vault, MINTER_ROLE on OutcomeToken.
- `src/Vault.sol` — BNB custody. PROTOCOL_ROLE for OrderBook/BatchAuction/Redemption.
- `src/MarketFactory.sol` — Market creation. ADMIN_ROLE for PythResolver.
- `src/PythResolver.sol` — Oracle integration. Admin = deployer (not AccessControl).

## How to Run

```bash
~/.foundry/bin/forge build
~/.foundry/bin/forge test -vv
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
