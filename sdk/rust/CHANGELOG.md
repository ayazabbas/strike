# Changelog

## v0.2.12 (2026-04-23)

### Fixed
- Updated built-in `StrikeConfig::bsc_mainnet()` contract addresses to the canonical 2026-04-23 mainnet deployment.
- Confirmed built-in `StrikeConfig::bsc_testnet()` contract addresses against the canonical 2026-04-23 testnet deployment.

## v0.2.11 (2026-04-11)

### Added
- Added `MarketsClient::market_meta()` for resolving on-chain factory market metadata, including whether a market uses internal positions.
- Added indexer helpers `get_positions()` and `get_redeemable_positions()` plus normalized position types for filled and redeemable wallet payloads.

## v0.2.10 (2026-04-05)

### Changed
- Replaced naive fixed gas allocation in order submission with deterministic contract-aware heuristics:
  - `placeOrders`: `550k + 175k * (n - 1)`
  - `replaceOrders`: `300k + 120k * cancels + 180k * places`
  - `cancelOrders`: `120k + 70k * count`
  - `cancelOrder`: `250k`
- Added SDK logging for `gas_limit`, `gas_used`, and gas utilization percentage on order submission/confirmation paths.

## v0.2.9 (2026-04-04)

### Fixed
- `IndexerClient::get_orderbook()` now uses the live indexer route `/orderbook/{market_id}` instead of the stale `/markets/{market_id}/orderbook` path.
- SDK orderbook decoding now accepts the live indexer field name `total_lots` for book levels.
- `read_markets` example now reads orderbooks using `tradable_market_id()` and labels factory vs tradable IDs clearly.

## v0.2.5 (2026-04-03)

### Fixed
- Updated built-in `StrikeConfig::bsc_mainnet()` contract addresses to match the live rotated mainnet deployment.
- Updated built-in `StrikeConfig::bsc_testnet()` contract addresses to match the current testnet deployment.
- Removed the stale note claiming mainnet contracts were not yet deployed.

## v0.2.4 (2026-04-01)

### Fixed
- **Market ID domain bug**: indexer/API market responses now expose `orderbook_market_id` alongside the legacy/factory `id`.
- Added `factory_market_id`, `orderbook_market_id`, and `tradable_market_id()` to SDK `Market`.
- Added safer trading helpers like `place_market()` / `replace_market()` so callers trade with the correct OrderBook market ID instead of the legacy factory ID.
- Updated SDK examples/docs to use tradable OrderBook IDs for orderbook reads and order placement.
- `simple_bot` now bootstraps from current active markets on startup instead of waiting only for future `MarketCreated` events.

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
