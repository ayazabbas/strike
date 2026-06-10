# Access Control and Role Graph

Strike contracts use OpenZeppelin `AccessControl` unless noted. `PythResolver` uses a small custom admin model.

## Roles Overview

| Role | Defined In | Granted To | Purpose |
|------|------------|------------|---------|
| `DEFAULT_ADMIN_ROLE` | AccessControl contracts | Deployer/admin | Grant and revoke roles |
| `OPERATOR_ROLE` | OrderBook | BatchAuction, MarketFactory | Market lifecycle and batch operations |
| `PROTOCOL_ROLE` | Vault | OrderBook, BatchAuction, Redemption | Collateral and internal-position accounting |
| `MINTER_ROLE` | OutcomeToken | BatchAuction, Redemption | Mint/burn outcome tokens |
| `ESCROW_ROLE` | OutcomeToken | BatchAuction | Burn escrowed sell-order tokens |
| `ADMIN_ROLE` | MarketFactory | Deployer/admin, resolvers | Market state transitions and protocol params |
| `MARKET_CREATOR_ROLE` | MarketFactory | Approved creators/keepers | Create CLOB markets |

## OrderBook `OPERATOR_ROLE`

Used for:

- `registerMarket(minLots, batchInterval, expiryTime, useInternalPositions)`
- `haltMarket(marketId)` / `resumeMarket(marketId)`
- `deactivateMarket(marketId)`
- `advanceBatch(marketId)`
- `setLastClearingTick(marketId, tick)`
- `pullRestingOrders(marketId)`

Granted to **MarketFactory** for market registration/lifecycle and **BatchAuction** for clearing operations.

## Vault `PROTOCOL_ROLE`

Used for collateral and position accounting:

- `depositFor`, `withdrawTo`, `lock`, `unlock`
- `settleFill`, `redeemFromPool`
- `creditPosition`, `lockPosition`, `unlockPosition`, `redeemPosition`

Granted to **OrderBook**, **BatchAuction**, and **Redemption**.

## OutcomeToken Roles

- `MINTER_ROLE`: mint and burn YES/NO outcome tokens.
- `ESCROW_ROLE`: burn outcome tokens held in OrderBook escrow when sell orders fill.

## MarketFactory Roles

`ADMIN_ROLE` controls lifecycle/admin actions:

- `setResolving(factoryMarketId)`
- `setResolved(factoryMarketId, outcomeYes, settlementPrice)`
- `setCancelled(factoryMarketId)`
- `pauseFactory(paused)`
- `setDefaultParams(batchInterval, minLots, feeBps)`
- `setAIResolver(resolver)`

`MARKET_CREATOR_ROLE` is required for `createMarket`, `createMarketWithPositions`, and `createAIMarket`.

## PythResolver Admin

`PythResolver` has a custom `admin` with two-step transfer:

```solidity
pythResolver.setPendingAdmin(newAdmin);
pythResolver.acceptAdmin();
```

The admin can update confidence threshold parameters. Resolution submission/finalization is permissionless when valid Pyth data and timing requirements are met.
