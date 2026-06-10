# PythResolver.sol

Resolves orderbook markets with Pyth price updates.

## Resolution Flow

1. Anyone submits Pyth update data after market expiry by calling `resolveMarket(...)`.
2. The resolver pays Pyth's update fee from `msg.value`; excess ETH/BNB is refunded.
3. Pyth verifies the update data and returns a price for the market's configured feed and valid settlement window.
4. If this is the first valid submission, the market moves to `Resolving` and a 90-second finality window starts.
5. During the finality window, anyone can submit an earlier valid update that changes the outcome.
6. After finality, anyone can call `finalizeResolution(...)`; outcome rule is `price >= strike` → YES wins, `price < strike` → NO wins.

## Main Functions

```solidity
function resolveMarket(uint256 factoryMarketId, bytes[] calldata priceUpdateData)
    external
    payable

function finalizeResolution(uint256 factoryMarketId) external
```

`resolveMarket` requires at least `pyth.getUpdateFee(priceUpdateData)` in `msg.value`. The current core CLOB contracts do not pay a resolver bounty.

## Notes

- Price IDs are stored as `bytes32` in `MarketFactory.marketMeta`.
- Resolution is permissionless, but hosted keepers normally perform it.
- Confidence checks reject updates with too much price uncertainty.
- If a market cannot be resolved with valid Pyth data, the factory can move it through its configured fallback/cancellation flow.
