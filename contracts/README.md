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

### BSC Mainnet (deployed block `95210316`)

| Contract | Address |
|----------|---------|
| USDT | `0x55d398326f99059fF775485246999027B3197955` |
| FeeModel | `0xFd7538Ad9EFEe4fCE07924F65a30688044e0800C` |
| OutcomeToken | `0xdAA6810Ca9614e2246d2849Be2a9c818707e404B` |
| Vault | `0x43D5caC88a87560Db8040Bef16F0ce8871B4F7ee` |
| OrderBook | `0x71F7Bc523FFF296A049a45D08cBD39D39d3C047B` |
| BatchAuction | `0x9d66fa0Aad92bb4428947443c1135C06a0cbFFBb` |
| MarketFactory | `0x34E0BCC1619dBc6A00A23b70BbaD9F36b0483d82` |
| PythResolver | `0x3E0864BbC19ca92777BB4c2e02490fC0C7A44C5a` |
| AIResolver | `0x3e0D91480147802D9C41068d91b7878E7943a632` |
| Redemption | `0xcC1687A27133f06dB96aF4e00E5bA91411f9c999` |
| Pyth Core | `0x4D7E825f80bDf85e913E0DD2A2D54927e9dE1594` |

### BSC Testnet (deployed block `104337216`)

| Contract | Address |
|----------|---------|
| MockUSDT | `0xb242dc031998b06772C63596Bfce091c80D4c3fA` |
| FeeModel | `0x78F6102Ee4C13c0836c4E0CCfc501B74F83C01CD` |
| OutcomeToken | `0x612AAD13FB8Cc41D32933966FE88dac3277f6d2a` |
| Vault | `0xb7dE5e17633bd3E9F4DfeFdF2149F5725f9092Fe` |
| OrderBook | `0xF890b891F83f29Ce72BdD2720C1114ba16D5316c` |
| BatchAuction | `0x743e60a7AE108614dDCb5bBb4468c4187002969B` |
| MarketFactory | `0xB4a9D6Dc1cAE195e276638ef9Cc20e797Cb3f839` |
| PythResolver | `0x2a7fba2365CCbd648e5c82E4846AD7D53fa47108` |
| AIResolver | `0xE1C9DA3d9b00582951f25D35234F8580DE1646d9` |
| Redemption | `0x28de9b7536ecfeE55De0f34E0875037E08E14F88` |
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
