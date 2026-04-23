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
