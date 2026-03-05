# Developer Integration Guide

## ABI Locations

After building with `forge build`, ABIs are in `contracts/out/<Contract>.sol/<Contract>.json`. Extract the `abi` field:

```bash
jq '.abi' contracts/out/MarketFactory.sol/MarketFactory.json > abi/MarketFactory.json
```

Frontend ABIs are pre-extracted in `frontend/src/lib/contracts/abis/`.

## Contract Addresses

Addresses are printed as JSON by the deploy scripts. After deployment, save the output and use it to configure your application.

See [Deployments](contracts/deployments.md) for currently deployed addresses.

## Market ID Types

Strike uses two distinct market ID systems:

| ID | Type | Source | Used By |
|----|------|--------|---------|
| `factoryMarketId` | `uint256` | Sequential counter in MarketFactory | MarketFactory, PythResolver, Redemption, frontend |
| `orderBookMarketId` | `uint256` | Sequential counter in OrderBook | OrderBook, BatchAuction, Vault, OutcomeToken |

The mapping is stored in `MarketFactory.marketMeta[factoryMarketId].orderBookMarketId`.

**When to use which:**
- **User-facing / API:** Always use `factoryMarketId` — it's the canonical market identifier
- **Trading / order operations:** OrderBook and BatchAuction use `orderBookMarketId` internally
- **Token IDs:** OutcomeToken uses `orderBookMarketId` to derive YES/NO token IDs

## Common Operations

### Create a Market

```solidity
// Requires creation bond (default 0.01 BNB)
uint256 factoryMarketId = factory.createMarket{value: 0.01 ether}(
    priceId,       // bytes32 Pyth price feed ID
    strikePrice,   // int64 with expo=-8 (e.g. 50000_00000000 for $50k)
    duration,      // uint256 seconds until expiry
    batchInterval, // uint256 seconds between batches
    minLots        // uint128 minimum order size
);
```

### Deposit BNB + Place Order

```solidity
// 1. Deposit collateral
vault.deposit{value: collateralAmount}();

// 2. Place order
// Bid at tick 60 for 10 lots: collateral = 10 * LOT_SIZE * 60 / 100
uint256 orderId = orderBook.placeOrder(
    orderBookMarketId,
    Side.Bid,                    // 0 = Bid, 1 = Ask
    OrderType.GoodTilCancel,     // 0 = GTC, 1 = GTB
    60,                          // tick (1-99)
    10                           // lots
);
```

### Claim Fills After Batch

```solidity
// Anyone can trigger clearing (keepers do this automatically)
batchAuction.clearBatch(orderBookMarketId);

// Claim your fills
batchAuction.claimFills(orderId);
```

### Redeem After Resolution

```solidity
// Burns winning outcome tokens, receives BNB
redemption.redeem(factoryMarketId, tokenAmount);
```

## Collateral Formulas

All values in wei. `LOT_SIZE = 1e15` (0.001 BNB).

| Side | Collateral Required |
|------|-------------------|
| Bid (YES) | `lots × LOT_SIZE × tick / 100` |
| Ask (NO) | `lots × LOT_SIZE × (100 − tick) / 100` |

Tick represents the implied probability (1–99%). A bid at tick 60 means "willing to pay 60% of LOT_SIZE per lot for YES exposure."

## Reading Market State

```solidity
// Get full market metadata
(bytes32 priceId, int64 strikePrice, uint256 expiryTime, uint256 creationBond,
 address creator, MarketState state, bool outcomeYes, int64 settlementPrice,
 uint256 orderBookMarketId) = factory.marketMeta(factoryMarketId);

// Get batch result
(uint256 clearingTick, uint64 matchedLots, uint64 totalBidLots, uint64 totalAskLots,
 uint256 batchId, uint256 timestamp) = batchAuction.batchResults(orderBookMarketId, batchId);
```

## WebSocket / Indexer API

The Strike indexer (in the `strike-infra` repo) provides:
- REST API for market data, order book state, user positions
- WebSocket for real-time order book updates and batch clearing events

See the strike-infra documentation for API endpoints and schemas.
