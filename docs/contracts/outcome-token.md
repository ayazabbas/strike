# OutcomeToken.sol

ERC-1155 multi-token contract for binary outcome tokens.

## Token ID Scheme

```
YES token: marketId * 2
NO token:  marketId * 2 + 1
```

Deterministic — no registry or mapping needed.

## Functions

### `mintPair(marketId, amount)`
Deposit `amount` collateral → receive `amount` YES + `amount` NO tokens. Called via Vault integration. Only callable by protocol contracts.

### `burnPair(marketId, amount)`
Return `amount` YES + `amount` NO → receive `amount` collateral back. Available anytime (pre- and post-resolution).

### `redeem(marketId, amount)`
Post-resolution only. Burn `amount` winning tokens → receive `amount` collateral. Losing tokens have no redemption value.

## Access Control

- `mintPair` / `burnPair` / `redeem`: restricted to protocol contracts (Vault, OrderBook)
- Standard ERC-1155 transfers: unrestricted (tokens are freely transferable)
