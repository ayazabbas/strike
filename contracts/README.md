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

## Live Deployments

### BSC Mainnet (deployed block `94290419`)

| Contract | Address |
|----------|---------|
| USDT | `0x55d398326f99059fF775485246999027B3197955` |
| FeeModel | `0x10d479354013c20eC777569618186D79eE818D8a` |
| OutcomeToken | `0xdcA3d1Be0a181494F2bf46a5a885b2c2009574f3` |
| Vault | `0x2a6EA3F574264E6fA9c6F3c691dA01BE6DaC066f` |
| OrderBook | `0x1E7C9b93D2C939a433D87b281918508Eec7c9171` |
| BatchAuction | `0xCdd122520E9efbdb5bd1Cc246aE497c37c70bdBE` |
| MarketFactory | `0xcbBC04B2a3EfE858c7C3d159c56f194AF2a7eBac` |
| PythResolver | `0x101383ef333d5Cb7Cb154EAbcA68961e3ac5B1a4` |
| AIResolver | `0xb0606b7984a2AA36774e8865E76689f98D39eE6e` |
| Redemption | `0x9a46D6c017eDdA49832cC9eE315246d0B55E5804` |
| Pyth Core | `0x4D7E825f80bDf85e913E0DD2A2D54927e9dE1594` |

### BSC Testnet (deployed block `103312703`)

| Contract | Address |
|----------|---------|
| MockUSDT | `0xb242dc031998b06772C63596Bfce091c80D4c3fA` |
| FeeModel | `0x5b8fCB458485e5d63c243A1FA4CA45e4e984B1eE` |
| OutcomeToken | `0x92dFA493eE92e492Df7EB2A43F87FBcb517313a9` |
| Vault | `0xEd56fF9A42F60235625Fa7DDA294AB70698DF25D` |
| OrderBook | `0x9CF4544389d235C64F1B42061f3126fF11a28734` |
| BatchAuction | `0x8e4885Cb6e0D228d9E4179C8Bd32A94f28A602df` |
| MarketFactory | `0xa1EA91E7D404C14439C84b4A95cF51127cE0338B` |
| PythResolver | `0x9ddadD15f27f4c7523268CFFeb1A1b04FEEA32b9` |
| AIResolver | `0xe2aAec0A169D39FB12b43edacB942190b152439b` |
| Redemption | `0x98723a449537AF17Fd7ddE29bd7De8f5a7A1B9B2` |
| Pyth Core | `0x5744Cbf430D99456a0A8771208b674F27f8EF0Fb` |

## Build & Test

```bash
forge build
forge test
forge test --via-ir
forge test -vvv
```

## Tech Stack

- Solidity / Foundry
- OpenZeppelin AccessControl + ReentrancyGuard
- Pyth Core oracle (`@pythnetwork/pyth-sdk-solidity`)
