# Positions & Settlement

## Internal Positions (Current 5-Minute Markets)

Current 5-minute markets use **internal positions** tracked on-chain rather than ERC-1155 tokens. Each market has two sides: **UP** and **DOWN**.

### Position Tracking

Positions are stored in a mapping:

```
positions[user][marketId][side]
```

When your order fills, your position is credited internally. No tokens are minted or transferred.

### Collateral

Each lot represents **$0.01 of collateral** (LOT_SIZE = 1e16). When a bid and ask match at a clearing tick, the combined collateral from both sides equals $0.01 per lot — fully collateralized.

### Trading

Positions are what you trade on the orderbook:
- **Buying UP at $0.60** = paying $0.006 per lot for an UP position (implies 60% probability)
- **Selling UP at $0.60** = selling your UP position for $0.006 per lot
- Equivalently, **buying DOWN at $0.40** (since UP + DOWN = $0.01 per lot)

### Settlement (Post-Resolution)

Once a market resolves:
- **Winning positions** pay out at LOT_SIZE ($0.01) per lot in USDT
- **Losing positions** pay nothing

Batch settlement (collateral movement, position crediting) happens inline during `clearBatch`. After market resolution, winning positions are redeemed via `redeem()` on the Redemption contract.

### Example

You buy 1000 lots of UP at tick 60 (cost: 1000 x $0.01 x 60/100 = $6.00). The market resolves UP.

- Your 1000 UP lots pay out 1000 x $0.01 = $10.00
- Profit: $10.00 - $6.00 = $4.00 (before fees)

If the market resolves DOWN, your UP position is worth $0.

### Cancellation

If a market is cancelled (no valid Pyth update within deadline), all collateral is refunded. No one loses funds.

## ERC-1155 Tokens (Future Market Types)

The contracts include a full ERC-1155 multi-token system (`OutcomeToken`) for future market types that may require transferable, composable tokens.

### Token IDs

Token IDs are deterministic — no registry needed:
- **UP:** `marketId * 2`
- **DOWN:** `marketId * 2 + 1`

### Minting & Merging

For token-based markets, outcome tokens are minted as fully collateralized pairs and can be merged back into collateral. Since tokens are ERC-1155, they are transferable and composable with other protocols.

This system is not active for current 5-minute markets but is available in the contracts for future use (controlled by the `useInternalPositions` flag on market creation).
