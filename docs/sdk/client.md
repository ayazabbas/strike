# Client Configuration

## Creating a Client

Use `StrikeClient::new()` with a config, then chain builder methods:

```rust
use strike_sdk::prelude::*;

// Mainnet with defaults
let client = StrikeClient::new(StrikeConfig::bsc_mainnet()).build()?;

// With a wallet for trading
let client = StrikeClient::new(StrikeConfig::bsc_mainnet())
    .with_private_key("0x...")
    .build()?;
```

## Preset Configs

| Method | Chain ID | Description |
|--------|----------|-------------|
| `StrikeConfig::bsc_mainnet()` | 56 | BSC mainnet with default RPC, WSS, and indexer URLs |
| `StrikeConfig::bsc_testnet()` | 97 | BSC testnet with default RPC, WSS, and indexer URLs |
| `StrikeConfig::custom(addresses, chain_id)` | any | Custom deployment |

Each preset includes default RPC, WSS, and indexer endpoints. Override any of them with builder methods.

## Builder Methods

```rust
let client = StrikeClient::new(StrikeConfig::bsc_mainnet())
    .with_rpc("https://your-rpc-node.com")       // override RPC endpoint
    .with_wss("wss://your-ws-node.com")           // override WSS endpoint
    .with_indexer("https://your-indexer.com")      // override indexer URL
    .with_private_key(&std::env::var("PRIVATE_KEY").unwrap())
    .build()?;
```

All builder methods are optional. A client built without `with_private_key()` is read-only — it can query markets, stream events, and read balances, but cannot send transactions.

## Read-Only vs Trading Mode

| Capability | Read-only | With wallet |
|-----------|-----------|-------------|
| Fetch markets, orderbook | Yes | Yes |
| Stream events | Yes | Yes |
| Read balances | Yes | Yes |
| Place/cancel orders | No | Yes |
| Approve USDT | No | Yes |
| Redeem tokens | No | Yes |

Calling a write method without a wallet returns `StrikeError::NoWallet`.

## Nonce Manager

For bots that send transactions in rapid succession, enable the nonce manager to avoid nonce-too-low errors:

```rust
let mut client = StrikeClient::new(StrikeConfig::bsc_mainnet())
    .with_private_key(&key)
    .build()?;

// Initialize the shared nonce tracker
client.init_nonce_sender().await?;
```

The `NonceSender` fetches the current nonce from the chain at init, then tracks it locally. It auto-recovers on nonce errors by re-syncing with the chain and retrying. Enabled by the `nonce-manager` feature flag (on by default).

You generally don't need this for simple scripts — it's designed for bots that place and cancel orders in tight loops.

## Accessing Internals

For advanced usage, you can access the underlying provider and config:

```rust
let provider = client.provider();      // &DynProvider — raw alloy provider
let config = client.config();           // &StrikeConfig — addresses and URLs
let addr = client.signer_address();     // Option<Address>
let block = client.block_number().await?;
```

## Sub-Clients

The `StrikeClient` exposes domain-specific sub-clients:

| Method | Returns | Description |
|--------|---------|-------------|
| `client.orders()` | `OrdersClient` | [Place, cancel, replace orders](orders.md) |
| `client.vault()` | `VaultClient` | [USDT approval and balance queries](vault-and-tokens.md) |
| `client.tokens()` | `TokensClient` | [ERC-1155 outcome token operations](vault-and-tokens.md) |
| `client.markets()` | `MarketsClient` | On-chain market state reads |
| `client.redeem()` | `RedeemClient` | [Post-resolution token redemption](vault-and-tokens.md) |
| `client.events()` | `EventStream` | [WSS event subscription](events.md) |
| `client.indexer()` | `IndexerClient` | [REST indexer client](indexer.md) |

## Error Handling

All SDK methods return `strike_sdk::Result<T>`, which is `std::result::Result<T, StrikeError>`.

```rust
use strike_sdk::prelude::*;

match client.orders().place(market_id, &params).await {
    Ok(orders) => { /* success */ }
    Err(StrikeError::NoWallet) => { /* no private key configured */ }
    Err(StrikeError::Rpc(e)) => { /* RPC transport error */ }
    Err(StrikeError::Contract(msg)) => { /* on-chain revert */ }
    Err(e) => { /* other error */ }
}
```

`StrikeError` variants:

| Variant | Cause |
|---------|-------|
| `Rpc` | Transport-level RPC failure |
| `Contract` | On-chain revert or ABI decoding error |
| `NonceMismatch` | Local nonce diverged from chain |
| `MarketNotActive` | Market ID is not active |
| `InsufficientBalance` | Not enough USDT or tokens |
| `NoWallet` | Write operation attempted without a private key |
| `WebSocket` | WSS connection error |
| `Indexer` | Indexer HTTP error |
| `Config` | Invalid configuration |
| `Other` | Catch-all via `eyre::Report` |
