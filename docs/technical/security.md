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
| `pruneExpiredOrders()` | Anyone (permissionless) |
| `claimFills()` / `redeem()` | Token/order holders |
| `createMarket()` | Anyone (with sufficient creation bond) |
| `pause()` / `unpause()` | Owner |
| `setFeeCollector()` | Owner |

### Bounded Iteration
No function iterates over unbounded sets. Segment trees provide O(log N) operations. Claim and prune functions require explicit order ID arrays from callers.

### Emergency Controls
- **Pausable:** owner can pause market creation and trading protocol-wide or per-market
- **24h auto-cancel:** markets without resolution auto-cancel, enabling full refunds
- **Emergency withdrawal:** users can withdraw via timelock if admin is unresponsive

### Anti-Spam
- Minimum lot sizes prevent dust orders
- Full collateral locking creates economic cost for spam (capital locked until fill or cancel)

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
- **Full collateralization:** all orders backed by locked collateral or outcome tokens
- **No leverage:** no margin, no liquidation risk
- **Deterministic halt:** trading stops when `timeRemaining < batchInterval`, preventing last-second exploitation
- Funds cannot be locked — cancellation/withdrawal always available

## Planned Auditing
- Slither static analysis
- Mythril symbolic execution
- Aderyn / 4naly3er additional coverage
- All high/medium findings addressed before mainnet
