# FeeModel.sol

Fee-calculation contract for the Strike CLOB protocol. It performs no transfers; callers such as Vault and BatchAuction move funds.

Inherits: `AccessControl`.

## Fee Schedule

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `feeBps` | `uint256` | Uniform total fee in basis points | 20 (0.20%) |
| `protocolFeeCollector` | `address` | Address that receives protocol fees | deployer |

**Constant:** `MAX_BPS = 10_000` (100%).

There is no maker/taker distinction. For buy-vs-sell-token matches, the total fee is split across buyer and seller; the seller side receives the rounding-up half. For normal Bid/Ask matches, the buyer-side locked fee funds the protocol fee.

## Calculation Functions

### `calculateFee(amount)`

Returns the total fee for a given filled collateral amount.

Formula: `fee = amount * feeBps / 10_000`

### `calculateHalfFee(amount)`

Returns `ceil(calculateFee(amount) / 2)`. BatchAuction uses this as the sell-side fee when a token/position seller receives a payout.

### `calculateOtherHalfFee(amount)`

Returns `calculateFee(amount) - calculateHalfFee(amount)`. BatchAuction uses this for the buyer side in buy-vs-sell-token matches.

## Admin Functions

All admin functions require `DEFAULT_ADMIN_ROLE`.

### `setFeeBps(_feeBps)`

Updates the uniform fee. Reverts if `_feeBps > MAX_BPS`.

### `setProtocolFeeCollector(_collector)`

Updates the protocol fee collector address. Reverts if `_collector` is the zero address.

## Events

| Event | Parameters | Description |
|-------|------------|-------------|
| `FeeBpsUpdated` | `uint256 feeBps` | Emitted when fee changes |
| `ProtocolFeeCollectorUpdated` | `address indexed collector` | Emitted when fee collector changes |

## Example

With `feeBps = 20`:

- Filled collateral: 100 USDT
- Total fee: `100 * 20 / 10000 = 0.20 USDT`
- Split fee: `0.10 USDT` / `0.10 USDT` before integer rounding
- Recipient: protocol fee collector
