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
