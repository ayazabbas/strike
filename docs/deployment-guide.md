# Deployment Guide

## Prerequisites

- [Foundry](https://book.getfoundry.sh/) installed (`forge`, `anvil`, `cast`)
- BNB for gas fees
- Deployer EOA private key
- BscScan API key (for contract verification)

## Environment Variables

```bash
export PRIVATE_KEY=0x...                # Deployer private key
export RPC_URL=https://...              # BSC RPC endpoint
export PYTH_ADDRESS=0x...              # Pyth Core contract address (see table below)
export ETHERSCAN_API_KEY=...           # BscScan API key for verification
```

### Pyth Oracle Addresses

| Network | Chain ID | Pyth Core Address |
|---------|----------|-------------------|
| BSC Testnet | 97 | `0x5744Cbf430D99456a0A8771208b674F27f8EF0Fb` |
| BSC Mainnet | 56 | `0x4D7E825f80bDf85e913E0DD2A2D54927e9dE1594` |

## Deployment Order

Contracts must be deployed in this exact order because of immutable constructor references:

```
1. Vault              -- no dependencies
2. OutcomeToken        -- no dependencies
3. FeeModel            -- no dependencies
4. OrderBook           -- needs Vault
5. BatchAuction        -- needs OrderBook, Vault, FeeModel, OutcomeToken
6. MarketFactory       -- needs OrderBook, OutcomeToken
7. PythResolver        -- needs Pyth oracle address, MarketFactory
8. Redemption          -- needs MarketFactory, OutcomeToken, Vault
```

### Constructor Arguments

| Contract | Constructor Args |
|----------|-----------------|
| `Vault(admin)` | deployer address |
| `OutcomeToken(admin)` | deployer address |
| `FeeModel(admin, feeBps, protocolFeeCollector)` | deployer, 20, deployer |
| `OrderBook(admin, vault)` | deployer, Vault address |
| `BatchAuction(admin, orderBook, vault, feeModel, outcomeToken)` | deployer, OrderBook, Vault, FeeModel, OutcomeToken |
| `MarketFactory(admin, orderBook, outcomeToken, feeCollector)` | deployer, OrderBook, OutcomeToken, deployer |
| `PythResolver(pyth, factory)` | PYTH_ADDRESS, MarketFactory |
| `Redemption(factory, outcomeToken, vault)` | MarketFactory, OutcomeToken, Vault |

## Role Wiring

After all contracts are deployed, grant the following roles. The deployer holds `DEFAULT_ADMIN_ROLE` on every AccessControl contract and can call `grantRole`.

### OrderBook.OPERATOR_ROLE

```solidity
orderBook.grantRole(OPERATOR_ROLE, address(batchAuction));
orderBook.grantRole(OPERATOR_ROLE, address(marketFactory));
```

BatchAuction needs OPERATOR_ROLE to call `reduceOrderLots`, `updateTreeVolume`, and `advanceBatch`. MarketFactory needs it to call `registerMarket` and `deactivateMarket`.

### Vault.PROTOCOL_ROLE

```solidity
vault.grantRole(PROTOCOL_ROLE, address(orderBook));
vault.grantRole(PROTOCOL_ROLE, address(batchAuction));
vault.grantRole(PROTOCOL_ROLE, address(redemption));
```

OrderBook calls `lock` and `unlock`. BatchAuction calls `settleFill` and `unlock`. Redemption calls `redeemFromPool`.

### OutcomeToken.MINTER_ROLE

```solidity
outcomeToken.grantRole(MINTER_ROLE, address(batchAuction));
outcomeToken.grantRole(MINTER_ROLE, address(redemption));
```

BatchAuction calls `mintSingle` during inline settlement. Redemption calls `redeem` (burns winning tokens).

### MarketFactory.ADMIN_ROLE

```solidity
factory.grantRole(ADMIN_ROLE, address(pythResolver));
```

PythResolver calls `setResolving`, `setResolved`, and `payResolverBounty` on MarketFactory.

### PythResolver Admin

PythResolver uses simple ownership (not AccessControl). The admin is set to `msg.sender` in the constructor (the deployer). Transfer via two-step process:

```solidity
pythResolver.setPendingAdmin(newAdmin);   // called by current admin
pythResolver.acceptAdmin();               // called by newAdmin
```

## Deploy Commands

### Local Devnet (Anvil)

For local development and testing:

```bash
anvil --chain-id 31337

forge script script/Deploy.s.sol \
  --rpc-url http://localhost:8545 \
  --broadcast
```

The `Deploy.s.sol` script deploys a `MockPyth` instance, wires all roles, and creates a test market automatically.

### BSC

```bash
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

The deploy script auto-detects chain ID and uses the correct Pyth address.

## Contract Verification

Deploy scripts pass `--verify` to auto-verify on BscScan. To verify a contract manually:

```bash
forge verify-contract <CONTRACT_ADDRESS> src/MarketFactory.sol:MarketFactory \
  --chain-id 56 \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode \
    "constructor(address,address,address,address)" \
    $DEPLOYER $ORDERBOOK $OUTCOMETOKEN $FEECOLLECTOR)
```

For contracts with complex constructor args, use `cast abi-encode` to produce the correct encoding.

## Post-Deploy Validation Checklist

1. **Contract verification** -- all contracts verified on BscScan.

2. **Role wiring** -- confirm every role grant:
   ```bash
   cast call $ORDERBOOK "hasRole(bytes32,address)(bool)" \
     $(cast keccak "OPERATOR_ROLE") $BATCH_AUCTION
   # Repeat for every grant listed above
   ```

3. **Role checks:**
   - `OrderBook.hasRole(OPERATOR_ROLE, BatchAuction)` -- true
   - `OrderBook.hasRole(OPERATOR_ROLE, MarketFactory)` -- true
   - `Vault.hasRole(PROTOCOL_ROLE, OrderBook)` -- true
   - `Vault.hasRole(PROTOCOL_ROLE, BatchAuction)` -- true
   - `Vault.hasRole(PROTOCOL_ROLE, Redemption)` -- true
   - `OutcomeToken.hasRole(MINTER_ROLE, BatchAuction)` -- true
   - `OutcomeToken.hasRole(MINTER_ROLE, Redemption)` -- true
   - `MarketFactory.hasRole(ADMIN_ROLE, PythResolver)` -- true

4. **Test market creation** -- call `MarketFactory.createMarket(...)` with a known Pyth price ID (requires MARKET_CREATOR_ROLE) and verify the market appears in `activeMarkets`.

5. **Test place/cancel cycle** -- approve Vault for USDT, call `OrderBook.placeOrder(...)` and verify USDT collateral is escrowed in Vault. Cancel the order and verify USDT is returned to wallet.

6. **Keepers configured** -- batch-keeper, market-keeper, and resolution-keeper (in strike-infra) pointing at correct contract addresses.

7. **Indexer configured** -- indexer (in strike-infra) pointing at correct RPC and contract addresses, listening for all relevant events.
