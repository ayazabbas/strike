# Access Control and Role Graph

All Strike contracts that use role-based access control inherit OpenZeppelin's `AccessControl`, except PythResolver which uses a simpler custom ownership model.

## Roles Overview

| Role | Defined In | Granted To | Purpose |
|------|-----------|------------|---------|
| `DEFAULT_ADMIN_ROLE` | All AccessControl contracts | Deployer EOA | Can grant/revoke any role |
| `OPERATOR_ROLE` | OrderBook | BatchAuction, MarketFactory | Manage markets and settle orders |
| `PROTOCOL_ROLE` | Vault | OrderBook, BatchAuction, Redemption | Lock/unlock/transfer collateral |
| `MINTER_ROLE` | OutcomeToken | BatchAuction, Redemption | Mint and burn outcome tokens |
| `ESCROW_ROLE` | OutcomeToken | BatchAuction | Burn escrowed sell-order tokens on fill via `burnEscrow()` |
| `ADMIN_ROLE` | MarketFactory | PythResolver | Manage market state transitions |

## Role Definitions

### DEFAULT_ADMIN_ROLE (all contracts)

```
bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
```

Held by the deployer EOA. Can call `grantRole` and `revokeRole` on any role. This is the OpenZeppelin default admin role that governs all other roles.

### OPERATOR_ROLE (OrderBook)

```
bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
```

Grants access to:
- `registerMarket(minLots, batchInterval, expiryTime)` -- create a new trading market
- `haltMarket(marketId)` / `resumeMarket(marketId)` -- pause/resume trading
- `deactivateMarket(marketId)` -- permanently close a market
- `reduceOrderLots(orderId, lotsToReduce)` -- remove filled lots from an order
- `updateTreeVolume(marketId, side, tick, delta)` -- adjust segment tree after fills
- `advanceBatch(marketId)` -- increment the batch counter

Granted to **BatchAuction** (settlement operations) and **MarketFactory** (market lifecycle).

### PROTOCOL_ROLE (Vault)

```
bytes32 public constant PROTOCOL_ROLE = keccak256("PROTOCOL_ROLE");
```

Grants access to:
- `lock(user, amount)` -- lock collateral for open orders
- `unlock(user, amount)` -- unlock collateral on cancel/prune
- `transferCollateral(from, to, amount)` -- move locked funds between accounts
- `settleFill(user, marketId, toPool, feeCollector, protocolFee, unlockAmount)` -- combined settlement
- `addToMarketPool(user, marketId, amount)` -- move funds into redemption pool
- `redeemFromPool(marketId, to, amount)` -- pay out from redemption pool

Granted to **OrderBook** (lock/unlock on order placement/cancel), **BatchAuction** (settlement), and **Redemption** (payout from pool).

### MINTER_ROLE (OutcomeToken)

```
bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
```

Grants access to:
- `mintPair(to, marketId, amount)` -- mint YES + NO token pair
- `mintSingle(to, marketId, amount, isYes)` -- mint a single outcome token
- `burnPair(from, marketId, amount)` -- burn YES + NO token pair
- `redeem(from, marketId, amount, winningOutcome)` -- burn winning tokens

Granted to **BatchAuction** (mints tokens during atomic settlement in `clearBatch`) and **Redemption** (burns winning tokens during redemption).

### ESCROW_ROLE (OutcomeToken)

```
bytes32 public constant ESCROW_ROLE = keccak256("ESCROW_ROLE");
```

Grants access to:
- `burnEscrow(from, marketId, amount, isYes)` -- burn escrowed outcome tokens held by OrderBook when sell orders (SellYes/SellNo) are filled during batch settlement

Granted to **BatchAuction**. When a SellYes or SellNo order is filled, the tokens were custodied by OrderBook on placement. BatchAuction calls `burnEscrow()` to burn those tokens as part of the settlement flow.

### ADMIN_ROLE (MarketFactory)

```
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
```

Grants access to:
- `setResolving(factoryMarketId)` -- transition market to Resolving state
- `setResolved(factoryMarketId, outcomeYes, settlementPrice)` -- finalize resolution
- `payResolverBounty(factoryMarketId, resolver)` -- pay creation bond to resolver
- `pauseFactory(paused)` -- pause/unpause market creation
- `setDefaultParams(batchInterval, minLots)` -- update default market params
- `setCreationBond(bond)` -- update creation bond amount
- `setFeeCollector(collector)` -- update fee collector

Granted to **PythResolver** (resolution state transitions) and the **deployer** (admin controls). Note: the deployer also receives `ADMIN_ROLE` in the MarketFactory constructor.

### PythResolver Admin (custom ownership)

PythResolver does not use OpenZeppelin AccessControl. It has a simple `admin` address set to `msg.sender` in the constructor. Transfer uses a two-step pattern:

```solidity
// Step 1: Current admin sets pending
pythResolver.setPendingAdmin(newAdmin);

// Step 2: New admin accepts
pythResolver.acceptAdmin();   // must be called by newAdmin
```

The admin can call:
- `setConfThreshold(newBps)` -- update confidence interval threshold

## Role Graph (ASCII)

```
                         Deployer EOA
                             |
              +--------------+--------------+
              |              |              |
       DEFAULT_ADMIN    DEFAULT_ADMIN   DEFAULT_ADMIN
       (OrderBook)      (Vault)         (OutcomeToken)
              |              |              |
              |              |              |
       OPERATOR_ROLE   PROTOCOL_ROLE   MINTER_ROLE
       (OrderBook)      (Vault)        (OutcomeToken)
         /      \        / | \           /      \
        v        v      v  v  v         v        v
  BatchAuction  MarketFactory          BatchAuction
                    |       OrderBook       |
                    |       BatchAuction    Redemption
                    |       Redemption
                    |
             DEFAULT_ADMIN + ADMIN_ROLE
              (MarketFactory)
                    |
               ADMIN_ROLE
              (MarketFactory)
                    |
                    v
              PythResolver ---------> admin (deployer EOA)
             (custom ownership)       setPendingAdmin / acceptAdmin
```

Detailed flow diagram:

```
  +---------------+  OPERATOR_ROLE   +-------------+
  | BatchAuction  |----------------->|  OrderBook  |
  +---------------+                  +-------------+
        |                                  |
        | PROTOCOL_ROLE                    | PROTOCOL_ROLE
        v                                  v
  +---------------+                  +-------------+
  |     Vault     |<-----------------| (lock/unlock)|
  +---------------+                  +-------------+
        ^
        | PROTOCOL_ROLE
        |
  +---------------+
  |  Redemption   |
  +---------------+
        |
        | MINTER_ROLE
        v
  +---------------+
  | OutcomeToken  |<---- MINTER_ROLE ---- BatchAuction
  +---------------+

  +---------------+  ADMIN_ROLE      +----------------+
  | PythResolver  |----------------->| MarketFactory  |
  +---------------+                  +----------------+
                                           |
                                           | OPERATOR_ROLE
                                           v
                                     +-------------+
                                     |  OrderBook  |
                                     +-------------+
```

## Wiring Commands

Run these after deployment (the deployer must hold `DEFAULT_ADMIN_ROLE` on each contract):

```solidity
// OrderBook: grant OPERATOR_ROLE
orderBook.grantRole(orderBook.OPERATOR_ROLE(), address(batchAuction));
orderBook.grantRole(orderBook.OPERATOR_ROLE(), address(marketFactory));

// Vault: grant PROTOCOL_ROLE
vault.grantRole(vault.PROTOCOL_ROLE(), address(orderBook));
vault.grantRole(vault.PROTOCOL_ROLE(), address(batchAuction));
vault.grantRole(vault.PROTOCOL_ROLE(), address(redemption));

// OutcomeToken: grant MINTER_ROLE
outcomeToken.grantRole(outcomeToken.MINTER_ROLE(), address(batchAuction));
outcomeToken.grantRole(outcomeToken.MINTER_ROLE(), address(redemption));

// OutcomeToken: grant ESCROW_ROLE
outcomeToken.grantRole(outcomeToken.ESCROW_ROLE(), address(batchAuction));

// MarketFactory: grant ADMIN_ROLE
factory.grantRole(factory.ADMIN_ROLE(), address(pythResolver));
```

## Security Notes

- The deployer holds `DEFAULT_ADMIN_ROLE` on all contracts. This should be transferred to a multisig or timelock for production deployments.
- PythResolver admin should also be transferred to a multisig via `setPendingAdmin` / `acceptAdmin`.
- Role grants are additive -- `grantRole` does not revoke existing holders.
- Missing role grants will cause `AccessControl: account ... is missing role ...` reverts at runtime.
