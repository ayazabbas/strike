# Changelog

## v0.2.3 (2026-03-28)

### Fixed
- **OrderResting event tracking**: `place()` and `replace()` now parse both `OrderPlaced` and `OrderResting` events from transaction receipts. Orders placed far from the clearing price (>20 ticks from last clearing tick) are added to the resting list on-chain and emit `OrderResting` instead of `OrderPlaced`. Previously these orders were invisible to the SDK, causing callers to lose track of live orders.
- Added `OrderResting` event to the OrderBook ABI.

## v0.2.2 (2026-03-24)

### Fixed
- Gas price floor: removed 5 gwei hardcoded floor from `NonceSender`. Alloy now auto-selects EIP-1559 fees. Added 0.05 gwei BSC minimum floor (`BSC_MIN_GAS_PRICE`) to meet Chainstack requirements.
- `apply_gas_floor()` applied to `gas_price`, `max_fee_per_gas`, and `max_priority_fee_per_gas` on both initial send and retry.

## v0.2.1 (2026-03-23)

### Added
- `NonceSender::read_provider()` — exposes the underlying provider for read-only calls without locking the nonce mutex.

## v0.2.0 (2026-03-24)

### Changed
- API v1 envelope format: indexer responses now use `{ data, meta }` pagination. SDK handles both v1 and legacy formats transparently.
- `get_markets()` fetches active markets by default.

### Added
- `replaceOrders` — atomic cancel + place in one transaction.
- `NonceSender` — shared nonce management with automatic retry on nonce conflicts.
- AI market fields in `Market` struct: `is_ai_market`, `ai_prompt`, `ai_status`.

## v0.1.0 (2026-03-22)

Initial release.
- `StrikeClient` builder with read-only and trading modes.
- Order placement, cancellation, and batch operations.
- WSS event subscriptions with auto-reconnect.
- Historical event scanning.
- Indexer REST client.
- USDT approval and vault operations.
- Outcome token redemption.
