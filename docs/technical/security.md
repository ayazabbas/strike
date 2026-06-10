# Security

## Smart Contract Security

### Reentrancy Protection

External state-changing functions use OpenZeppelin `ReentrancyGuard` where needed, and follow checks-effects-interactions.

### Access Control

| Function | Access |
|----------|--------|
| `placeOrder()` / `cancelOrder()` | Anyone with sufficient balance/approval |
| `clearBatch()` | Anyone |
| `resolveMarket()` | Anyone with valid Pyth data and update fee |
| `finalizeResolution()` | Anyone after finality |
| `redeem()` | Eligible token/position holders |
| `createMarket()` | `MARKET_CREATOR_ROLE` |
| `pauseFactory()` / lifecycle admin actions | `ADMIN_ROLE` |
| `setProtocolFeeCollector()` | `DEFAULT_ADMIN_ROLE` on FeeModel |

### Bounded Iteration

Segment trees provide O(log N) price-level operations. Order counts and resting-order scans are capped. Batch settlement is chunked (`SETTLE_CHUNK_SIZE = 400`) so gas per `clearBatch` call remains bounded.

### Emergency Controls

- Markets can be halted/resumed or deactivated by authorized operators.
- Unresolved markets can be cancelled through the configured fallback path, enabling refunds.
- Vault emergency mode has a timelock before emergency withdrawals.

### Anti-Spam / DoS Prevention

- Minimum lot sizes prevent dust orders.
- Full collateral locking creates an economic cost for spam.
- `MAX_USER_ORDERS = 20` per market prevents a single address from flooding the book.
- Resting orders far from the clearing price are parked outside the active segment tree while still locking collateral.

## Oracle Security

### Pyth Integration

- Pyth update data is verified on-chain.
- `parsePriceFeedUpdates` reads the settlement-window price without relying on a pre-updated on-chain price.
- Confidence checks reject updates with excessive uncertainty.
- Fallback windows handle rare Pyth publishing delays.

### Resolution Safety

- First valid submission starts a 90-second finality window.
- During finality, an earlier valid update can challenge only if it changes the outcome.
- Finalization is permissionless after the finality window.
- Each market can only be finalized once.

## Trading Safety

- Orderbook trades are fully collateralized with locked USDT or locked positions.
- Pool markets are backed by their configured collateral.
- No margin or liquidation mechanics.
- Users can cancel open orders while the market is active.

## Auditing

### Internal Audit v1.2

An internal security audit (v1.2) covered the core contracts, including fee split logic, chunked settlement, resting orders, and per-user order caps. See [Internal Audit v1.2](internal-audit-v1.2.md).

### World Cup Multiplier Cross-Event Ticket Internal Review

An internal Codex-assisted review covered the World Cup Multiplier cross-event Prediction Ticket refactor. This was not an external third-party audit. See [World Cup Multiplier Cross-Event Ticket Internal Review](world-cup-multiplier-predictions-v0-audit.md).
