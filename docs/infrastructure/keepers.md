# Keepers

Keepers are off-chain services that call permissionless contract functions to keep the protocol running. They are **not trusted** — anyone can run a keeper, and the protocol works correctly regardless of which keeper submits a transaction.

## Batch Clearing Keeper

Calls `clearBatch(marketId)` on active markets. The keeper decides clearing cadence — there is no on-chain batch interval enforcement.

- Monitors pending order volume via segment tree reads
- Skips clearing if no crossing orders (saves gas)
- Gas estimation + exponential backoff on failures
- Multi-market scheduling: round-robin or priority by volume
- Settlement is atomic — all orders in the batch are settled inline (no separate claim step)

```bash
# Configuration
BATCH_KEEPER_RPC_URL=https://...
BATCH_KEEPER_PRIVATE_KEY=0x...
BATCH_KEEPER_INTERVAL_MS=3000
BATCH_KEEPER_GAS_LIMIT=2000000
```

## Resolution Keeper

Resolves expired markets with Pyth oracle data.

- Watches for markets entering `Closed` state
- Fetches signed update data from Pyth Hermes: `GET /v2/updates/price/{publishTime}?ids[]={priceId}`
- Submits `resolveMarket()` then `finalizeResolution()` after finality window
- Handles fallback window extension if initial fetch has no data
- Claims resolver bounty on success

Note: No pruning keeper is needed. Markets expire naturally and `clearBatch()` handles all settlement atomically.

## Monitoring

- Keepers log all actions with timestamps and gas costs
- Alert on: missed clearing intervals, failed resolutions, RPC errors
- Health endpoint: `GET /health` returns keeper status and last action timestamp
