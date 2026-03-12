# Outcome Tokens

Strike uses **ERC-1155 multi-tokens** to represent market outcomes. Each market has two tokens: YES and NO.

## Token IDs

Token IDs are deterministic — no registry needed:
- **YES:** `marketId * 2`
- **NO:** `marketId * 2 + 1`

## Minting

Outcome tokens are always minted as a **fully collateralized pair**:

```
Deposit 1 USDT → Receive 1 YES + 1 NO
```

This guarantees that the total collateral in the system always equals the total supply of either token. There's no fractional reserve.

## Merging

At any time before resolution, you can merge a pair back into collateral:

```
Return 1 YES + 1 NO → Receive 1 USDT
```

This is useful for exiting a position without trading on the book.

## Trading

Outcome tokens are what you trade on the orderbook:
- **Buying YES at 0.60** = paying 0.60 USDT for 1 YES token (implies 60% probability)
- **Selling YES at 0.60** = selling 1 YES token for 0.60 USDT
- Equivalently, **buying NO at 0.40** (since YES + NO = 1.00)

Since tokens are ERC-1155, they're transferable and composable with other protocols.

## Redemption (Post-Resolution)

Once a market resolves:
- **Winning tokens** redeem 1:1 for collateral (1 winning token → 1 USDT)
- **Losing tokens** are worthless (can be burned or ignored)

### Example

You buy 10 YES tokens at 0.60 each (cost: 6 USDT). The market resolves YES.

- Your 10 YES tokens redeem for 10 USDT
- Profit: 10 - 6 = 4 USDT (before fees)

If the market resolves NO, your YES tokens are worth 0.

## Cancellation

If a market is cancelled (no valid Pyth update within deadline), all token pairs can be merged back to collateral. No one loses funds.
