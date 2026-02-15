# Market.sol

The core prediction market contract. Each instance represents a single UP/DOWN prediction on BTC/USD price.

## Key Functions

### `initialize()`

Called once by the factory after cloning. Sets up the market parameters.

```solidity
function initialize(
    address _pyth,
    bytes32 _priceId,
    uint256 _duration,
    address _factory,
    address _feeCollector,
    bytes[] calldata pythUpdateData
) external payable
```

- Fetches the current Pyth price as the **strike price**
- Sets `tradingEnd = now + duration/2`
- Sets `expiryTime = now + duration`

### `bet(Side side)`

Place a bet on UP or DOWN.

```solidity
function bet(Side side) external payable whenNotPaused nonReentrant
```

- Minimum bet: 0.001 BNB
- Must be called before `tradingEnd`
- Early bets receive bonus shares (up to 2x multiplier at market open)
- Emits `BetPlaced` event

### `resolve(bytes[] pythUpdateData)`

Resolve the market using Pyth price data.

```solidity
function resolve(bytes[] calldata pythUpdateData) external payable nonReentrant
```

- Can be called by **anyone** after `expiryTime`
- Verifies Pyth price data on-chain
- Determines winning side (UP if price > strike, DOWN if price < strike)
- Cancels if: one-sided market, exact tie, or empty pool
- Deducts 3% protocol fee from winning pool

### `claim()`

Claim your winnings from a resolved market.

```solidity
function claim() external nonReentrant
```

- Only callable after market is Resolved
- Payout = (your shares / total winning shares) × (total pool - fee)
- Can only claim once

### `refund()`

Get your money back from a cancelled market.

```solidity
function refund() external nonReentrant
```

- Only callable after market is Cancelled
- Returns exact amount bet (no fees)

## Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `MIN_BET` | 0.001 BNB | Minimum bet size |
| `PROTOCOL_FEE_BPS` | 300 (3%) | Fee on winning pool |
| `RESOLUTION_DEADLINE` | 24 hours | Auto-cancel if unresolved |
| `PRICE_MAX_AGE` | 60 seconds | Max staleness for Pyth price |
| `MAX_MULTIPLIER` | 2x | Early bird share multiplier |

## Events

| Event | When |
|-------|------|
| `BetPlaced(user, side, amount, shares)` | Bet successfully placed |
| `MarketResolved(winningSide, price, resolver)` | Market resolved |
| `MarketCancelled(reason)` | Market cancelled |
| `Claimed(user, payout)` | Winnings claimed |
| `Refunded(user, amount)` | Bet refunded |

## Inheritance

- `ReentrancyGuard` (OpenZeppelin) — prevents reentrancy attacks
- `Pausable` (OpenZeppelin) — emergency pause capability
