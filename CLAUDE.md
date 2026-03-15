# Strike — CLAUDE.md

## Project Overview

Strike is a fully on-chain prediction market protocol on BNB Chain. Traders buy and sell binary outcome tokens (YES/NO) on whether an asset's price will be above or below a strike price at expiry. Uses Frequency Batch Auctions (FBA) for fair price discovery.

## V2 Contract Architecture

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

## Key V7 Design Decisions (SellYes/SellNo)

- **4-sided orderbook**: `Side` enum has `Bid`, `Ask`, `SellYes`, `SellNo`. SellYes/SellNo let token holders sell back into the book.
- **Token custody**: OrderBook is `ERC1155Holder`. Sell orders transfer tokens in; cancel/non-fill returns them; fill burns them via `burnEscrow`.
- **placeOrder signature changed**: `(marketId, side, orderType, tick, lots)` — note `orderType` is now 3rd param (was 4th).
- **SellYes payout**: at clearing tick, `lots * clearingTick / 100 * LOT_SIZE` USDT from pool.
- **SellNo payout**: at clearing tick, `lots * (100 - clearingTick) / 100 * LOT_SIZE` USDT from pool.
- **User flow**: approve `OutcomeToken.setApprovalForAll(OrderBook, true)` once, then place SellYes/SellNo orders.
- **ESCROW_ROLE**: new role on OutcomeToken, granted to BatchAuction. Used by `burnEscrow()`.

## Key V2 Design Decisions

- **USDT collateral** (not BNB): 1 YES + 1 NO = 1 USDT. LOT_SIZE = 1e18. Users approve Vault before trading.
- **Atomic clearBatch(marketId)**: No orderIds param. Contract reads `batchOrderIds[marketId][batchId]` internally. No separate claim step.
- **Clearing price settlement**: All fills pay the clearing tick, not their limit tick. Excess refund = (locked at order tick) - (cost at clearing tick).
- **Uniform 20bps fee**: No maker/taker. `clearingBountyBps` exists but set to 0.
- **Batch overflow**: MAX_ORDERS_PER_BATCH = 400, spills to next batch when full.
- **GTC/GTB**: GTC rolls unfilled remainder to next batch. GTB auto-expires if unfilled.
- **No pruning**: Markets expire naturally. No pruneExpiredOrder function.
- **No on-chain batch interval enforcement**: Keeper decides clearing cadence.
- **Permissioned market creation**: Requires MARKET_CREATOR_ROLE (no creation bond).

## BSC Testnet V7 Addresses (deployed 2026-03-15, SellYes/SellNo)

- MockUSDT: `0xb242dc031998b06772C63596Bfce091c80D4c3fA`
- FeeModel: `0x5c49f364FfE404B041e1f44cCd3801Ea9d328034`
- OutcomeToken: `0xaCbc1Ad38cF2767Ac57c5a23105e73A7DE319AEB`
- Vault: `0x54DB2d048547b9b9426699833f3B57ab03b5F8dc`
- OrderBook: `0x0B8557c02CCD2E59571fDc56D16ac2b5fC3E14D2`
- BatchAuction: `0xd378411231665898E2cdB4c0e1cD723f6C696DA3`
- MarketFactory: `0x9d6FC94A14a393Dd7b3F2FfBa0110D06010aD4a2`
- PythResolver: `0x10CCAbaE996AE13403DbD9a6b1C38456D7B08bE9`
- Redemption: `0x0eB52824d38E5682B876A79166C8B1045A0BBb2B`
- Pyth Core: `0xd7308b14BF4008e7C7196eC35610B1427C5702EA`

## Tests

```bash
cd contracts
forge test        # 267 tests
forge test -vvv   # verbose output
```

## Coding Conventions

- Solidity: Foundry project, OpenZeppelin AccessControl + ReentrancyGuard
- Frontend: Next.js 16, wagmi v3, viem v2.45, @reown/appkit 1.8
- ABIs extracted from `contracts/out/` to `frontend/src/lib/contracts/abis/`
- Pyth Core (not Lazer) for oracle resolution
- Price IDs stored as bytes32 in MarketFactory.marketMeta
