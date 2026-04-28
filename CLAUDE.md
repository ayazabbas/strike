# Strike — CLAUDE.md

## Project Overview

Strike is a fully on-chain prediction market protocol (v1) on BNB Chain. Traders buy and sell binary outcome tokens (YES/NO) on whether an asset's price will be above or below a strike price at expiry. Uses Frequent Batch Auctions (FBA) for fair price discovery.

## Contract Architecture

8 core contracts + 1 library, all singletons with per-market state via mappings:

| Contract | Role |
|----------|------|
| **OrderBook** | Order placement, cancellation, segment trees, per-batch order tracking |
| **BatchAuction** | Atomic `clearBatch(marketId)` — clears + settles all orders inline |
| **Vault** | USDT (ERC-20) collateral escrow via SafeERC20 (transferFrom/transfer) |
| **MarketFactory** | Market lifecycle, permissioned creation (MARKET_CREATOR_ROLE) |
| **FeeModel** | Uniform fee calculation (20 bps), no maker/taker distinction |
| **OutcomeToken** | ERC-1155 YES/NO tokens |
| **PythResolver** | Pyth Core oracle resolution via `parsePriceFeedUpdates` |
| **Redemption** | Post-resolution token redemption for USDT |
| **SegmentTree** | Library for O(log N) clearing tick computation |

## Key Design Decisions

- **4-sided orderbook**: `Side` enum has `Bid`, `Ask`, `SellYes`, `SellNo`. SellYes/SellNo let token holders sell back into the book.
- **Token custody**: OrderBook is `ERC1155Holder`. Sell orders transfer tokens in; cancel/non-fill returns them; fill burns them via `burnEscrow`.
- **placeOrder signature**: `(marketId, side, orderType, tick, lots)` — orderType is 3rd param.
- **Batch order functions**: `placeOrders(OrderParam[])` for batch placement, `replaceOrders(cancelIds, OrderParam[])` for atomic cancel+place, `cancelOrders(orderIds)` for batch cancel.
- **USDT collateral**: 1 YES + 1 NO = 1 USDT. LOT_SIZE = 1e16 ($0.01/lot). Users approve Vault before trading.
- **Atomic clearBatch(marketId)**: No orderIds param. Contract reads `batchOrderIds[marketId][batchId]` internally. No separate claim step.
- **Clearing price settlement**: All fills pay the clearing tick, not their limit tick. Excess refund = (locked at order tick) - (cost at clearing tick).
- **Uniform 20bps fee**: No maker/taker. `clearingBountyBps` exists but set to 0.
- **Batch overflow**: MAX_ORDERS_PER_BATCH = 400, spills to next batch when full.
- **GTC/GTB**: GTC rolls unfilled remainder to next batch. GTB auto-expires if unfilled.
- **Permissioned market creation**: Requires MARKET_CREATOR_ROLE (no creation bond).
- **ESCROW_ROLE**: Role on OutcomeToken, granted to BatchAuction. Used by `burnEscrow()`.
- **SellYes payout**: at clearing tick, `lots * clearingTick / 100 * LOT_SIZE` USDT from pool.
- **SellNo payout**: at clearing tick, `lots * (100 - clearingTick) / 100 * LOT_SIZE` USDT from pool.

## BSC Testnet Addresses (current)

- MockUSDT: `0xb242dc031998b06772C63596Bfce091c80D4c3fA`
- FeeModel: `0x78F6102Ee4C13c0836c4E0CCfc501B74F83C01CD`
- OutcomeToken: `0x612AAD13FB8Cc41D32933966FE88dac3277f6d2a`
- Vault: `0xb7dE5e17633bd3E9F4DfeFdF2149F5725f9092Fe`
- OrderBook: `0xF890b891F83f29Ce72BdD2720C1114ba16D5316c`
- BatchAuction: `0x743e60a7AE108614dDCb5bBb4468c4187002969B`
- MarketFactory: `0xB4a9D6Dc1cAE195e276638ef9Cc20e797Cb3f839`
- PythResolver: `0x2a7fba2365CCbd648e5c82E4846AD7D53fa47108`
- AIResolver: `0xE1C9DA3d9b00582951f25D35234F8580DE1646d9`
- Redemption: `0x28de9b7536ecfeE55De0f34E0875037E08E14F88`
- Pyth Core: `0x5744Cbf430D99456a0A8771208b674F27f8EF0Fb`

## Tests

```bash
cd contracts
forge test        # 292 tests
forge test -vvv   # verbose output
```

## Coding Conventions

- Solidity: Foundry project, OpenZeppelin AccessControl + ReentrancyGuard
- Frontend: Next.js 16, wagmi v3, viem v2.45, @reown/appkit 1.8
- ABIs extracted from `contracts/out/` to `frontend/src/lib/contracts/abis/`
- Pyth Core (not Lazer) for oracle resolution
- Price IDs stored as bytes32 in MarketFactory.marketMeta
