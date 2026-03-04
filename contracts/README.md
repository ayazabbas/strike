# Strike CLOB Contracts

Binary outcome prediction market with Frequent Batch Auctions on BNB Chain.

## Architecture

| Contract | Purpose |
|---|---|
| `OrderBook.sol` | Central limit order book with segment tree price matching |
| `BatchAuction.sol` | Periodic FBA clearing, pro-rata settlement, outcome token minting |
| `Vault.sol` | BNB custody, collateral locking, market pool escrow |
| `OutcomeToken.sol` | ERC-1155 YES/NO outcome tokens per market |
| `FeeModel.sol` | Taker fee / maker rebate calculation, protocol fee collector |
| `MarketFactory.sol` | Market creation, lifecycle state machine, resolver bounty |
| `PythResolver.sol` | Pyth Lazer oracle resolution with finality gate + challenge period |
| `Redemption.sol` | Post-resolution burn-to-redeem (winning tokens → BNB) |
| `SegmentTree.sol` | Fixed-size segment tree (99 ticks) for O(log n) clearing |

## Market Lifecycle

```
Open → Closed → Resolving → Resolved
                                ↓
Open → Closed ──────────────→ Cancelled (no resolution within 24h)
```

- **Open**: orders accepted, batches clear at `batchInterval`
- **Closed**: no new orders (market expired), final batch clears
- **Resolving**: Pyth price submitted, 3-block finality gate, challengers can submit earlier data
- **Resolved**: outcome set (YES/NO), redemption open
- **Cancelled**: no resolution within 24h of expiry, bond refunded

## Resolution (Pyth Lazer)

1. Anyone calls `resolveMarket()` with a Pyth Lazer update containing `(price, confidence)`
2. Confidence must be within 1% of price; data must be in one of 5 fallback windows post-expiry
3. Resolution enters 3-block finality gate; challengers can submit earlier `publishTime`
4. After finality, `finalizeResolution()` sets outcome and pays resolver bounty

## Collateral Model

- **Bids** lock `lots * LOT_SIZE * tick / 100` BNB (price willing to pay)
- **Asks** lock `lots * LOT_SIZE * (100 - tick) / 100` BNB (complementary risk)
- Both sides' collateral sums to `LOT_SIZE` per matched lot
- On settlement, collateral moves to market pool; winners redeem at `LOT_SIZE` per token

## Build & Test

```shell
~/.foundry/bin/forge build
~/.foundry/bin/forge test -vv
```

## Project Structure

```
src/
  ITypes.sol          — shared types (Order, Market, BatchResult, enums)
  SegmentTree.sol     — segment tree library for 99-tick range
  OrderBook.sol       — order placement, cancellation, tree management
  BatchAuction.sol    — batch clearing, pro-rata settlement, token minting
  Vault.sol           — deposit/withdraw, lock/unlock, market pool
  OutcomeToken.sol    — ERC-1155 YES/NO token pairs
  FeeModel.sol        — fee schedule (BPS-based)
  MarketFactory.sol   — market creation + state machine
  PythResolver.sol    — Pyth Lazer oracle integration
  Redemption.sol      — post-resolution token redemption
test/
  BatchAuction.t.sol  — clearing, settlement, prune, pro-rata tests
  Integration.t.sol   — full lifecycle, multi-user, gas snapshots
  OrderBook.t.sol     — order placement, cancellation, tree tests
  PythResolver.t.sol  — resolution, challenge, finality tests
  SegmentTree.t.sol   — tree operations, clearing tick algorithm
  MarketFactory.t.sol — creation, state transitions, admin controls
```
