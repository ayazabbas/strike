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

## BSC Testnet V6 Addresses (deployed 2026-03-15, batchCancel)

- MockUSDT: `0xb7FFc63715fA15047DCf3b16b0036AD05c3D04F7`
- FeeModel: `0xe94398B40b9e564E23c4c7dB6115F031B135B678`
- OutcomeToken: `0x4FA0E346dC388C5A0dFFb7E7a801463CBDfe300B`
- Vault: `0xc97B3f5F9dac0e6cC05a7e44a791aF1Ec199392e`
- OrderBook: `0x3D20998b135A4800cD7717D0504366F62C3DD641`
- BatchAuction: `0x558822b9Fd5be9905200d799A85A721f78a7a0f0`
- MarketFactory: `0x997A4Ad2249BED986463046DC070b1BB6e0E60A4`
- PythResolver: `0x96df2608f7c8DCAA4013700502C99531C4299F69`
- Redemption: `0xA51a642D840154536EAd35437BeaDB9ED088511d`
- Pyth Core: `0xd7308b14BF4008e7C7196eC35610B1427C5702EA`

## Tests

```bash
cd contracts
forge test        # 249 tests
forge test -vvv   # verbose output
```

## Coding Conventions

- Solidity: Foundry project, OpenZeppelin AccessControl + ReentrancyGuard
- Frontend: Next.js 16, wagmi v3, viem v2.45, @reown/appkit 1.8
- ABIs extracted from `contracts/out/` to `frontend/src/lib/contracts/abis/`
- Pyth Core (not Lazer) for oracle resolution
- Price IDs stored as bytes32 in MarketFactory.marketMeta
