# OutcomeToken.sol

> **Note:** Current 5-minute markets use internal positions (`useInternalPositions = true`) and do not mint ERC-1155 tokens. This contract is used for future market types that require transferable outcome tokens.

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

## Events

```solidity
event PairMinted(address indexed to, uint256 indexed marketId, uint256 amount);
event PairBurned(address indexed from, uint256 indexed marketId, uint256 amount);
event Redeemed(address indexed from, uint256 indexed marketId, uint256 amount, bool winningOutcome);
```
