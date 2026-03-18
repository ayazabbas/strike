# Strike Contracts (v1)

Fully on-chain prediction market protocol on BNB Chain. Binary outcome tokens (YES/NO) traded via a Central Limit Order Book (CLOB) with Frequent Batch Auctions (FBA) for fair price discovery.

## Architecture

8 core contracts + 1 library, all singletons with per-market state via mappings:

| Contract | Role |
|----------|------|
| **OrderBook** | Order placement, cancellation, segment trees, per-batch order tracking |
| **BatchAuction** | Atomic `clearBatch(marketId)` — clears + settles all orders inline |
| **Vault** | USDT (ERC-20) collateral escrow via SafeERC20 |
| **MarketFactory** | Market lifecycle, permissioned creation (MARKET_CREATOR_ROLE) |
| **FeeModel** | Uniform fee calculation (20 bps), no maker/taker distinction |
| **OutcomeToken** | ERC-1155 YES/NO tokens per market |
| **PythResolver** | Pyth Core oracle resolution via `parsePriceFeedUpdates` |
| **Redemption** | Post-resolution token redemption for USDT |
| **SegmentTree** | Library for O(log N) clearing tick computation |

## Key Features

- **4-sided orderbook:** `Side` enum: `Bid`, `Ask`, `SellYes`, `SellNo`. SellYes/SellNo let token holders sell back into the book.
- **USDT collateral:** 1 YES + 1 NO = 1 USDT. `LOT_SIZE = 1e16` ($0.01/lot).
- **Order types:** `GoodTilCancel` (GTC) persists across batches; `GoodTilBatch` (GTB) expires after one batch.
- **Order functions:** `placeOrder` (single), `placeOrders` (batch), `replaceOrders` (atomic cancel+place), `cancelOrder`, `cancelOrders` (batch cancel).
- **Atomic clearing:** `clearBatch(marketId)` — no orderIds param, no separate claim step.
- **Token custody:** OrderBook is `ERC1155Holder`. Sell orders transfer tokens in; cancel/non-fill returns them; fill burns them via `burnEscrow`.
- **Pyth Core oracle:** Resolution via `parsePriceFeedUpdates`. Price IDs stored as `bytes32` in `MarketFactory.marketMeta`.
- **99-tick range:** Ticks 1-99, each = 1% probability. Segment tree binary search for clearing price.

## BSC Testnet Addresses (v1)

| Contract | Address |
|----------|---------|
| MockUSDT | `0xb242dc031998b06772C63596Bfce091c80D4c3fA` |
| FeeModel | `0xf5b6889a56f9d95c059be028e682f802aee6c074` |
| OutcomeToken | `0xc398678d4eb9b5a67dd3b2ff9cd6c517140fcf65` |
| Vault | `0x04606a6f4909d0e9d9d763083d7649a2229eb679` |
| OrderBook | `0x9675bab261a6f168dd76fedb6d8706021e338c16` |
| BatchAuction | `0x62224a55d05175eaeb22fc6263355c820c77e849` |
| MarketFactory | `0xf3ad14f117348de4886c29764fdcaf9c62794535` |
| PythResolver | `0x5e7b8bb9d18bc620a19cea78caaf51e1ab8afa92` |
| Redemption | `0xd181cc898bbbf4d2ddaebf6f245f043dd8f93704` |
| Pyth Core | `0xd7308b14BF4008e7C7196eC35610B1427C5702EA` |

## Build & Test

```bash
forge build
forge test          # 292 tests
forge test -vvv     # verbose output
```

## Tech Stack

- Solidity / Foundry
- OpenZeppelin AccessControl + ReentrancyGuard
- Pyth Core oracle (`@pythnetwork/pyth-sdk-solidity`)
