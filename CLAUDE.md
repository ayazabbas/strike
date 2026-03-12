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

## BSC Testnet V2 Addresses (deployed 2026-03-12)

- MockUSDT: `0x4Be5501EDDF6263984614840A13228D0ecbf8430`
- Vault: `0xf7c51CC50F1589082850978BA8E779318299FeC9`
- OrderBook: `0xAFeeF2F0DBE473e4C2BC4b5981793F69804CfaD0`
- BatchAuction: `0xDB15B4BDC2A2595BbC03af25f225668c098e0ACC`
- MarketFactory: `0x5b562aeD5db8e4799565F1092d3D2b3C851909b7`
- PythResolver: `0x23a2553eD776bEE953cC4378F1BCcCe83eDF9BB3`
- Redemption: `0x850DfD796FBb88f576D7136C5f205Cf2AEc01e74`
- Pyth Core: `0xd7308b14BF4008e7C7196eC35610B1427C5702EA`

## Tests

```bash
cd contracts
forge test        # 244 tests
forge test -vvv   # verbose output
```

## Coding Conventions

- Solidity: Foundry project, OpenZeppelin AccessControl + ReentrancyGuard
- Frontend: Next.js 16, wagmi v3, viem v2.45, @reown/appkit 1.8
- ABIs extracted from `contracts/out/` to `frontend/src/lib/contracts/abis/`
- Pyth Core (not Lazer) for oracle resolution
- Price IDs stored as bytes32 in MarketFactory.marketMeta
