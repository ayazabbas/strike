# Local Devnet Setup

Run the full Strike protocol locally using Foundry's Anvil.

## Prerequisites

Install [Foundry](https://book.getfoundry.sh/getting-started/installation):

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

This provides three tools:
- `anvil` -- local Ethereum node
- `forge` -- build, test, and deploy Solidity contracts
- `cast` -- CLI for interacting with contracts

## Start Anvil

```bash
anvil --chain-id 31337
```

Anvil starts with 10 pre-funded accounts (each with 10,000 ETH). The default account (index 0) is:

- Address: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`
- Private key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

Leave this terminal running.

## Deploy

In a new terminal, from the project root:

```bash
cd contracts

forge script script/Deploy.s.sol \
  --rpc-url http://localhost:8545 \
  --broadcast
```

The deploy script:

1. Deploys all 9 contracts (FeeModel, OutcomeToken, Vault, OrderBook, BatchAuction, MockPyth, MarketFactory, PythResolver, Redemption)
2. Wires all access control roles
3. Creates a test market (BTC/USD, strike price $50,000, 1-hour duration, 12-second batch intervals)
4. Prints all contract addresses as JSON to stdout

Save the JSON output -- you will need the addresses for subsequent commands.

## Useful Cast Commands

Set up address variables from the deploy output:

```bash
export RPC=http://localhost:8545
export PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export VAULT=<vault address from deploy output>
export ORDERBOOK=<orderbook address>
export BATCH_AUCTION=<batchAuction address>
export FACTORY=<marketFactory address>
export RESOLVER=<pythResolver address>
export REDEMPTION=<redemption address>
export MOCK_PYTH=<mockPyth address>
```

### Approve & Deposit USDT

On devnet, a MockUSDT is deployed. Approve the Vault, then place orders (deposit happens automatically):

```bash
export USDT=<mockUSDT address from deploy output>

# Approve Vault to spend USDT
cast send $USDT "approve(address,uint256)" $VAULT 1000000000000000000000 \
  --rpc-url $RPC \
  --private-key $PK
```

### Check Balance

```bash
cast call $VAULT "balance(address)(uint256)" \
  0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --rpc-url $RPC
```

### Place a Bid Order

Place a bid at tick 60 for 10 lots on orderBookMarketId 1:

```bash
cast send $ORDERBOOK "placeOrder(uint256,uint8,uint8,uint256,uint256)" \
  1 0 1 60 10 \
  --rpc-url $RPC \
  --private-key $PK
```

Arguments: `marketId=1, side=0(Bid), orderType=1(GTC), tick=60, lots=10`.

Collateral required: `10 * 1e18 * 60 / 100 = 6e18 = 6 USDT`.

### Place an Ask Order

Place an ask at tick 60 for 10 lots (from a different account):

```bash
export PK2=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

# Approve Vault for USDT first
cast send $USDT "approve(address,uint256)" $VAULT 1000000000000000000000 \
  --rpc-url $RPC \
  --private-key $PK2

# Place ask
cast send $ORDERBOOK "placeOrder(uint256,uint8,uint8,uint256,uint256)" \
  1 1 1 60 10 \
  --rpc-url $RPC \
  --private-key $PK2
```

### Clear a Batch

Wait for the batch interval (12 seconds on the test market), then clear:

```bash
cast send $BATCH_AUCTION "clearBatch(uint256)" 1 \
  --rpc-url $RPC \
  --private-key $PK
```

Note: Settlement is atomic — all orders in the batch are settled inline during `clearBatch()`. No separate claim step is needed.

### Read Market State

```bash
# Factory market metadata
cast call $FACTORY "marketMeta(uint256)" 1 --rpc-url $RPC

# OrderBook market info
cast call $ORDERBOOK "markets(uint256)" 1 --rpc-url $RPC

# Batch result for market 1, batch 1
cast call $BATCH_AUCTION "getBatchResult(uint256,uint256)" 1 1 --rpc-url $RPC
```

### Check Volume at a Tick

```bash
# Bid volume at tick 60 for market 1
cast call $ORDERBOOK "bidVolumeAt(uint256,uint256)(uint256)" 1 60 --rpc-url $RPC

# Ask volume at tick 60 for market 1
cast call $ORDERBOOK "askVolumeAt(uint256,uint256)(uint256)" 1 60 --rpc-url $RPC
```

### Cancel an Order

```bash
cast send $ORDERBOOK "cancelOrder(uint256)" 1 \
  --rpc-url $RPC \
  --private-key $PK
```

### Withdraw from Vault

```bash
cast send $VAULT "withdraw(uint256)" 1000000000000000000 \
  --rpc-url $RPC \
  --private-key $PK
```

### Advance Block Time

Anvil supports time manipulation for testing resolution flows:

```bash
# Advance time by 1 hour (to reach market expiry)
cast rpc evm_increaseTime 3600 --rpc-url $RPC
cast rpc evm_mine --rpc-url $RPC
```

## MockPyth

The devnet deploy uses Pyth's `MockPyth` contract instead of the real Pyth oracle. To create mock price updates for resolution testing:

```solidity
// In a Forge script or test
bytes[] memory updateData = new bytes[](1);
updateData[0] = mockPyth.createPriceFeedUpdateData(
    priceId,        // bytes32
    price,          // int64 (e.g. 50000_00000000 for $50k with expo=-8)
    confidence,     // uint64
    expo,           // int32 (typically -8)
    emaPrice,       // int64
    emaConf,        // uint64
    publishTime     // uint64 (must be >= market expiryTime)
);
```

## Running Tests

```bash
cd contracts
forge test -vv
```

For a specific test file:

```bash
forge test --match-path test/OrderBook.t.sol -vvv
```

## Full Stack (with Infrastructure)

For batch clearing keepers and the indexer, see the [strike-infra](https://github.com/ayazabbas/strike-infra) repo. It provides:
- Batch clearing keeper
- Market resolution keeper
- Event indexer with REST/WebSocket API

## Troubleshooting

- **"insufficient available balance"** -- ensure you have approved the Vault for sufficient USDT before placing orders.
- **"too soon"** -- wait for the batch interval to elapse before calling `clearBatch` again, or use `cast rpc evm_increaseTime`.
- **"market halted"** / **"not active"** -- check the market state with `cast call $ORDERBOOK "markets(uint256)" <id>`.
- **Role errors** -- verify role wiring with `cast call <contract> "hasRole(bytes32,address)(bool)" <role_hash> <address>`.
