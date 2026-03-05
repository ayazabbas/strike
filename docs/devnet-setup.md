# Local Devnet Setup

## Prerequisites

- [Foundry](https://book.getfoundry.sh/) (`forge`, `anvil`, `cast`)
- Node.js 18+ (for frontend)

## Quick Start

### 1. Start Anvil

```bash
anvil --block-time 3
```

This starts a local chain at `http://127.0.0.1:8545` with 3-second block times.

### 2. Deploy Contracts

```bash
cd contracts
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

The script deploys all contracts, wires roles, and creates a test market. It prints deployed addresses as JSON.

### 3. Interact via Cast

```bash
# Deposit BNB
cast send $VAULT "deposit()" --value 1ether --private-key $PK --rpc-url http://127.0.0.1:8545

# Place a bid order
cast send $ORDERBOOK "placeOrder(uint256,uint8,uint8,uint256,uint256)" \
  1 0 0 50 10 \
  --private-key $PK --rpc-url http://127.0.0.1:8545

# Clear batch
cast send $BATCHAUCTION "clearBatch(uint256)" 1 \
  --private-key $PK --rpc-url http://127.0.0.1:8545
```

### 4. Run Tests

```bash
cd contracts
forge test        # all tests
forge test -vvvv  # verbose with traces
forge test --match-test test_ClearBatch  # filter by name
```

## Test Accounts

Anvil provides 10 pre-funded accounts. The deploy script uses account 0 as deployer:

```
Account 0 (deployer): 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
Private Key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

## MockPyth

The devnet deploy uses Pyth's `MockPyth` contract. To create mock price updates for resolution:

```bash
# Create mock price update (in your test/script)
bytes[] memory updateData = mockPyth.createPriceFeedUpdateData(
    priceId,      // bytes32
    price,        // int64 (e.g. 50000_00000000 for $50k)
    confidence,   // uint64
    expo,         // int32 (typically -8)
    emaPrice,     // int64
    emaConf,      // uint64
    publishTime   // uint64
);
```

## Full Stack (with Infrastructure)

For batch clearing keepers and the indexer, see the [strike-infra](https://github.com/ayazabbas/strike-infra) repo. It provides Docker-compose for:
- Batch clearing keeper
- Market resolution keeper
- Event indexer with REST/WebSocket API
