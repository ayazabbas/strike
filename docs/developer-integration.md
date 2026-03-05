# Developer Integration Guide

## ABI Locations

After building with `forge build`, full ABIs are emitted to:

```
contracts/out/<ContractName>.sol/<ContractName>.json
```

Extract the `abi` field for use in frontends or scripts:

```bash
jq '.abi' contracts/out/MarketFactory.sol/MarketFactory.json > abi/MarketFactory.json
```

Pre-extracted frontend ABIs are available in `frontend/src/lib/contracts/abis/`.

## Contract Addresses

Deploy scripts print all addresses as JSON to stdout. After deployment, save this output and use it to configure your application. See [Deployments](contracts/deployments.md) for currently deployed addresses.

## Interacting with Contracts

### Using wagmi/viem (TypeScript)

```typescript
import { readContract, writeContract } from '@wagmi/core';
import { parseEther } from 'viem';
import MarketFactoryABI from './abis/MarketFactory.json';
import VaultABI from './abis/Vault.json';
import OrderBookABI from './abis/OrderBook.json';

// Read market metadata
const meta = await readContract({
  address: MARKET_FACTORY_ADDRESS,
  abi: MarketFactoryABI,
  functionName: 'marketMeta',
  args: [factoryMarketId],
});

// Deposit BNB
await writeContract({
  address: VAULT_ADDRESS,
  abi: VaultABI,
  functionName: 'deposit',
  value: parseEther('0.1'),
});
```

### Using ethers.js (v6)

```typescript
import { Contract, parseEther } from 'ethers';

const vault = new Contract(VAULT_ADDRESS, VaultABI, signer);
await vault.deposit({ value: parseEther('0.1') });

const orderBook = new Contract(ORDERBOOK_ADDRESS, OrderBookABI, signer);
const tx = await orderBook.placeOrder(
  orderBookMarketId,
  0,   // Side.Bid
  1,   // OrderType.GoodTilCancel
  60,  // tick
  10   // lots
);
```

## Market ID Types

Strike uses two distinct market ID systems. Understanding the difference is critical.

| ID | Source | Used By |
|----|--------|---------|
| `factoryMarketId` | Sequential counter in `MarketFactory` | MarketFactory, PythResolver, Redemption, frontend |
| `orderBookMarketId` | Sequential counter in `OrderBook` | OrderBook, BatchAuction, Vault, OutcomeToken |

The mapping is stored in `MarketFactory.marketMeta[factoryMarketId].orderBookMarketId`.

**When to use which:**

- **User-facing / API:** Always use `factoryMarketId`. It is the canonical market identifier for resolution, redemption, and display.
- **Trading operations:** `OrderBook.placeOrder`, `BatchAuction.clearBatch`, and `BatchAuction.claimFills` use `orderBookMarketId`.
- **Token IDs:** `OutcomeToken` derives YES/NO token IDs from `orderBookMarketId` (`marketId*2` = YES, `marketId*2+1` = NO).

## Key Flows

### 1. Deposit Collateral

```solidity
vault.deposit{value: amount}();
```

Credits `msg.value` to the sender's balance in the Vault.

### 2. Place an Order

```solidity
uint256 orderId = orderBook.placeOrder(
    orderBookMarketId,           // from marketMeta
    Side.Bid,                    // 0 = Bid (YES), 1 = Ask (NO)
    OrderType.GoodTilCancel,     // 0 = GoodTilBatch, 1 = GoodTilCancel
    60,                          // tick (1-99, price = tick/100)
    10                           // lots (each = 0.001 BNB)
);
```

Collateral is locked in the Vault automatically:
- Bid: `lots * LOT_SIZE * tick / 100`
- Ask: `lots * LOT_SIZE * (100 - tick) / 100`

Where `LOT_SIZE = 1e15 wei = 0.001 BNB`.

### 3. Batch Clearing

```solidity
// Anyone can trigger (keepers do this automatically)
batchAuction.clearBatch(orderBookMarketId);
```

Finds the clearing tick via the segment tree and records the `BatchResult`. Enforces a minimum interval (`batchInterval` seconds) between clears.

### 4. Claim Fills

```solidity
batchAuction.claimFills(orderId);
```

Pro-rata settlement based on the clearing result:
- Filled collateral moves to the market's redemption pool in Vault.
- Protocol fee is deducted and sent to `protocolFeeCollector`.
- Unfilled collateral is unlocked (GoodTilBatch) or stays locked for the next batch (GoodTilCancel).
- Outcome tokens are minted: Bid fills receive YES tokens, Ask fills receive NO tokens.

### 5. Redeem After Resolution

```solidity
redemption.redeem(factoryMarketId, tokenAmount);
```

Burns `tokenAmount` winning outcome tokens and pays out `tokenAmount * LOT_SIZE` BNB from the market's redemption pool.

## Collateral Formulas

All values in wei. `LOT_SIZE = 1e15` (0.001 BNB).

| Side | Collateral Required |
|------|---------------------|
| Bid (YES) | `lots * LOT_SIZE * tick / 100` |
| Ask (NO) | `lots * LOT_SIZE * (100 - tick) / 100` |

Tick represents implied probability (1--99%). A bid at tick 60 means "willing to pay 60% of LOT_SIZE per lot for YES exposure."

## Reading Market State

```solidity
// Get full market metadata (factoryMarketId)
(bytes32 priceId, int64 strikePrice, uint256 expiryTime, uint256 creationBond,
 address creator, MarketState state, bool outcomeYes, int64 settlementPrice,
 uint256 orderBookMarketId) = factory.marketMeta(factoryMarketId);

// Get batch result (orderBookMarketId)
BatchResult memory result = batchAuction.getBatchResult(orderBookMarketId, batchId);
```

## Getting Price Data from Pyth Hermes API

PythResolver requires Pyth price update data. Fetch it from the Hermes REST API:

```bash
# Get price update for BTC/USD
curl "https://hermes.pyth.network/v2/updates/price/latest?ids[]=0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43"
```

In TypeScript:

```typescript
const HERMES_URL = 'https://hermes.pyth.network';

async function getPriceUpdate(priceId: string): Promise<string[]> {
  const resp = await fetch(
    `${HERMES_URL}/v2/updates/price/latest?ids[]=${priceId}`
  );
  const data = await resp.json();
  return data.binary.data.map((d: string) => '0x' + d);
}

// Use with PythResolver
const priceUpdateData = await getPriceUpdate(priceId);
const fee = await pythResolver.read.getPythUpdateFee([priceUpdateData]);

await pythResolver.write.resolveMarket(
  [factoryMarketId, priceUpdateData],
  { value: fee }
);
```

### Common Pyth Price Feed IDs

| Asset | Price Feed ID |
|-------|---------------|
| BTC/USD | `0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43` |
| BNB/USD | `0x2f95862b045670cd22bee3114c39763a4a08beeb663b145d283c31d7d1101c4f` |

## WebSocket / Indexer API

The Strike indexer (in the `strike-infra` repo) provides:
- REST API for market data, order book state, and user positions
- WebSocket for real-time order book updates and batch clearing events

See the strike-infra documentation for API endpoints and schemas.
