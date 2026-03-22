# FeeModel.sol

Pure fee-calculation contract for the Strike CLOB protocol. This contract performs no transfers -- all movement of funds is handled by callers (Vault, BatchAuction, etc.). FeeModel only computes amounts.

Inherits: `AccessControl` (OpenZeppelin).

## Fee Schedule

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `feeBps` | `uint256` | Uniform fee in basis points | 20 (0.20%) |
| `clearingBountyBps` | `uint256` | Bonus for clearing keeper (admin-configurable, currently disabled) | 0 |
| `protocolFeeCollector` | `address` | Address that receives the protocol's fee share | deployer |

**Constant:** `MAX_BPS = 10_000` (100%).

No maker/taker distinction — both sides of a trade pay half the fee (50/50 split). The extra wei from integer rounding goes to the protocol (sell side pays `ceil`).

## Calculation Functions

### calculateFee

```solidity
function calculateFee(uint256 amount) public view returns (uint256 fee)
```

Returns the total fee for a given filled collateral amount.

Formula: `fee = amount * feeBps / 10_000`

### calculateHalfFee

```solidity
function calculateHalfFee(uint256 amount) public view returns (uint256 fee)
```

Returns the buy-side half of the fee: `floor(calculateFee(amount) / 2)`.

### calculateOtherHalfFee

```solidity
function calculateOtherHalfFee(uint256 amount) public view returns (uint256 fee)
```

Returns the sell-side half of the fee: `calculateFee(amount) - calculateHalfFee(amount)` (i.e. `ceil(fee / 2)`). The sell-side fee is deducted from the seller's USDT payout at settlement.

## Admin Functions

All admin functions require `DEFAULT_ADMIN_ROLE`.

### setFeeBps

```solidity
function setFeeBps(uint256 _feeBps) external
```

Update the uniform fee. Reverts if `_feeBps > MAX_BPS`.

### setClearingBounty

```solidity
function setClearingBounty(uint256 _clearingBountyBps) external
```

Set the clearing bounty percentage (currently disabled, reserved for future use).

### setProtocolFeeCollector

```solidity
function setProtocolFeeCollector(address _collector) external
```

Update the protocol fee collector address. Reverts if `_collector` is the zero address.

## Events

| Event | Parameters | Description |
|-------|-----------|-------------|
| `FeeBpsUpdated` | `uint256 feeBps` | Emitted when fee changes |
| `ClearingBountyUpdated` | `uint256 clearingBountyBps` | Emitted when clearing bounty changes |
| `ProtocolFeeCollectorUpdated` | `address indexed collector` | Emitted when fee collector changes |

## Example

With default parameters (feeBps=20):

- Filled collateral: 100 USDT
- Total fee: 100 * 20 / 10000 = 0.20 USDT
- Buy-side fee: floor(0.20 / 2) = 0.10 USDT
- Sell-side fee: ceil(0.20 / 2) = 0.10 USDT
- To protocol fee collector: 0.20 USDT (sum of both halves)
