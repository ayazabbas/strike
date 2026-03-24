# Keepers

Keepers are off-chain services that call permissionless contract functions to keep the protocol running. They are **not trusted** — anyone can run a keeper, and the protocol works correctly regardless of which keeper submits a transaction.

## Unified Keeper

Strike runs a **unified keeper** — a single Rust binary with four concurrent tokio tasks:

| Task | Trigger | Description |
|------|---------|-------------|
| **Batch clearing** | Block-driven | Calls `clearBatch(marketId)` on active markets when new blocks arrive |
| **Market lifecycle** | Sleep-to-boundary | Sleeps until market expiry, then triggers close/resolve flow |
| **Resolution** | 5-second poll | 3-phase resolution: close expired markets → resolve via Pyth → finalize after 90s |
| **Pruning** | 10-second poll | Cleans up resolved, cancelled, and closed markets |

### Batch Clearing

- Monitors pending order volume via segment tree reads
- Skips clearing if no crossing orders (saves gas)
- Gas estimation + exponential backoff on failures
- Settlement is atomic — all orders in the batch are settled inline (no separate claim step)
- Settlement is chunked: SETTLE_CHUNK_SIZE = 400 orders per `clearBatch` call

### Resolution (3-Phase)

1. **Close** — detects expired markets and transitions them to `Closed` state
2. **Resolve** — fetches signed Pyth update data from Hermes and submits `resolveMarket()`
3. **Finalize** — after the 90-second finality period, calls `finalizeResolution()`

Admin `setResolved()` is available as a fallback if Pyth data is unavailable.

### Pruning

Covers resolved, cancelled, and closed markets. Cleans up stale state to keep keeper memory usage bounded.

## Configuration

```bash
KEEPER_RPC_URL=https://...
KEEPER_PRIVATE_KEY=0x...
KEEPER_GAS_LIMIT=2000000
```

## Monitoring

- Keepers log all actions with timestamps and gas costs
- Alert on: missed clearing intervals, failed resolutions, RPC errors
- Health endpoint: `GET /health` returns keeper status and last action timestamp
