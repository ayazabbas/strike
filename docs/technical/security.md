# Security

## Smart Contract Security

### Reentrancy Protection
All external state-changing functions use OpenZeppelin's `ReentrancyGuard`. The Checks-Effects-Interactions pattern is followed throughout.

### Access Control

| Function | Access |
|----------|--------|
| `placeOrder()` / `cancelOrder()` | Anyone (with sufficient balance) |
| `clearBatch()` | Anyone (permissionless) |
| `resolveMarket()` | Anyone (with valid Pyth data) |
| `finalizeResolution()` | Anyone (after finality window) |
| `redeem()` | Token holders |
| `createMarket()` | MARKET_CREATOR_ROLE |
| `pause()` / `unpause()` | Owner |
| `setFeeCollector()` | Owner |

### Bounded Iteration
No function iterates over unbounded sets. Segment trees provide O(log N) operations. Batch order count is capped at MAX_ORDERS_PER_BATCH (1600) with automatic overflow to the next batch. Settlement is chunked (SETTLE_CHUNK_SIZE = 400) so gas cost per `clearBatch` call remains bounded.

### Emergency Controls
- **Pausable:** owner can pause market creation and trading protocol-wide or per-market
- **24h auto-cancel:** markets without resolution auto-cancel, enabling full refunds
- **Emergency withdrawal:** users can withdraw via timelock if admin is unresponsive

### Anti-Spam / DoS Prevention
- Minimum lot sizes prevent dust orders
- Full collateral locking creates economic cost for spam (capital locked until fill or cancel)
- **Per-user active order cap:** MAX_USER_ORDERS = 20 per market prevents a single address from flooding the order book
- **Resting order list:** orders far from the clearing price (>20 ticks) are parked outside the segment tree, preventing phantom volume from distorting price discovery while still locking collateral

## Oracle Security

### Pyth Integration
- All price data is **cryptographically verified on-chain** via Wormhole attestations
- `parsePriceFeedUpdates` verifies settlement price on-chain (earliest update in window)
- **Confidence interval check** rejects settlement if price uncertainty exceeds threshold (default 1%)
- Fallback windows handle rare Pyth publishing delays

### Resolution Safety
- **Finality gate:** resolution waits for economic finality (n+2 blocks) before finalizing
- **Procedural challenge:** anyone can submit a better qualifying Pyth update during finality window
- **Replay protection:** each market can only be resolved once

## Trading Safety
- **Full collateralization:** all orders backed by locked USDT collateral
- **No leverage:** no margin, no liquidation risk
- **Deterministic halt:** trading stops when `timeRemaining < batchInterval`, preventing last-second exploitation
- Funds cannot be locked — cancellation/withdrawal always available

## Auditing

### Internal Audit v1.2
An internal security audit (v1.2) was conducted covering all core contracts. Key areas reviewed include fee split logic, chunked settlement, resting order mechanics, and per-user order caps. All findings have been addressed. See `docs/technical/internal-audit-v1.2.md` for the full report.

### Static Analysis
- Slither static analysis
- Mythril symbolic execution
- Aderyn / 4naly3er additional coverage
- All high/medium findings addressed before mainnet
