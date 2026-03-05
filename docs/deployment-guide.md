# Deployment Guide

## Prerequisites

- [Foundry](https://book.getfoundry.sh/) installed
- BNB for gas + creation bond (≥ 0.1 BNB recommended)
- Private key for deployer EOA

## Environment Variables

```bash
PRIVATE_KEY=0x...        # Deployer private key
RPC_URL=https://...      # BSC testnet or mainnet RPC
ETHERSCAN_API_KEY=...    # BscScan API key for verification
```

## Deployment Order

Contracts must be deployed in this order (immutable references require it):

1. **FeeModel** — no dependencies
2. **OutcomeToken** — no dependencies
3. **Vault** — no dependencies
4. **OrderBook** — needs Vault address
5. **BatchAuction** — needs OrderBook, Vault, FeeModel, OutcomeToken
6. **MarketFactory** — needs OrderBook, OutcomeToken
7. **PythResolver** — needs Pyth oracle address, MarketFactory
8. **Redemption** — needs MarketFactory, OutcomeToken, Vault

## Role Wiring

After all contracts are deployed, grant these roles:

```
OrderBook.grantRole(OPERATOR_ROLE, BatchAuction)
OrderBook.grantRole(OPERATOR_ROLE, MarketFactory)
Vault.grantRole(PROTOCOL_ROLE, OrderBook)
Vault.grantRole(PROTOCOL_ROLE, BatchAuction)
Vault.grantRole(PROTOCOL_ROLE, Redemption)
OutcomeToken.grantRole(MINTER_ROLE, BatchAuction)
OutcomeToken.grantRole(MINTER_ROLE, Redemption)
MarketFactory.grantRole(ADMIN_ROLE, PythResolver)
```

## Deploy Commands

### Local Devnet (Anvil)

```bash
# Start anvil
anvil

# Deploy with MockPyth
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

### BSC Testnet

```bash
forge script script/DeployTestnet.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### BSC Mainnet

```bash
forge script script/DeployTestnet.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

The deploy script auto-detects chain ID 97 (testnet) vs 56 (mainnet) and uses the correct Pyth address.

## Pyth Oracle Addresses

| Network | Pyth Core Address |
|---------|-------------------|
| BSC Testnet (97) | `0xd7308b14BF4008e7C7196eC35610B1427C5702EA` |
| BSC Mainnet (56) | `0x4D7E825f80bDf85e913E0DD2A2D54927e9dE1594` |

## Contract Verification

Deploy scripts pass `--verify` to auto-verify on BscScan. To verify manually:

```bash
forge verify-contract <address> src/MarketFactory.sol:MarketFactory \
  --chain-id 97 \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address,address,address,address)" $DEPLOYER $ORDERBOOK $OUTCOMETOKEN $FEECOLLECTOR)
```

## Post-Deploy Validation Checklist

1. All contracts verified on BscScan
2. Role wiring confirmed:
   - `OrderBook.hasRole(OPERATOR_ROLE, BatchAuction)` → true
   - `OrderBook.hasRole(OPERATOR_ROLE, MarketFactory)` → true
   - `Vault.hasRole(PROTOCOL_ROLE, OrderBook)` → true
   - `Vault.hasRole(PROTOCOL_ROLE, BatchAuction)` → true
   - `Vault.hasRole(PROTOCOL_ROLE, Redemption)` → true
   - `OutcomeToken.hasRole(MINTER_ROLE, BatchAuction)` → true
   - `OutcomeToken.hasRole(MINTER_ROLE, Redemption)` → true
   - `MarketFactory.hasRole(ADMIN_ROLE, PythResolver)` → true
3. Test market creation: call `MarketFactory.createMarket{value: 0.01 ether}(...)` with a known Pyth price ID
4. Test deposit/withdraw cycle on Vault
5. Keepers (strike-infra) configured with correct contract addresses
6. Indexer (strike-infra) pointing at correct RPC and contract addresses
