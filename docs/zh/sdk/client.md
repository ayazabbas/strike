# 客户端配置

## 创建客户端

使用 `StrikeClient::new()` 传入配置，然后链式调用 builder 方法：

```rust
use strike_sdk::prelude::*;

// Mainnet with defaults
let client = StrikeClient::new(StrikeConfig::bsc_mainnet()).build()?;

// With a wallet for trading
let client = StrikeClient::new(StrikeConfig::bsc_mainnet())
    .with_private_key("0x...")
    .build()?;
```

## 预设配置

| 方法 | 链 ID | 说明 |
|--------|----------|-------------|
| `StrikeConfig::bsc_mainnet()` | 56 | BSC 主网默认 RPC、WSS 和索引器 URL |
| `StrikeConfig::bsc_testnet()` | 97 | BSC 测试网默认 RPC、WSS 和索引器 URL |
| `StrikeConfig::custom(addresses, chain_id)` | any | 自定义部署 |

每个预设都包含默认的 RPC、WSS 和索引器 endpoint。可以使用 builder 方法覆盖任意一项。

## Builder 方法

```rust
let client = StrikeClient::new(StrikeConfig::bsc_mainnet())
    .with_rpc("https://your-rpc-node.com")       // override RPC endpoint
    .with_wss("wss://your-ws-node.com")           // override WSS endpoint
    .with_indexer("https://your-indexer.com")      // override indexer URL
    .with_private_key(&std::env::var("PRIVATE_KEY").unwrap())
    .build()?;
```

所有 builder 方法都是可选的。未调用 `with_private_key()` 构建的客户端是只读客户端，可以查询市场、订阅事件和读取余额，但不能发送交易。

## 只读模式与交易模式

| 能力 | 只读 | 使用钱包 |
|-----------|-----------|-------------|
| 获取市场和订单簿 | Yes | Yes |
| 订阅事件流 | Yes | Yes |
| 读取余额 | Yes | Yes |
| 提交或取消订单 | No | Yes |
| 授权 USDT | No | Yes |
| 赎回代币 | No | Yes |

在没有钱包的情况下调用写入方法会返回 `StrikeError::NoWallet`。

## Nonce Manager

如果 bot 会连续快速发送交易，可以启用 nonce manager 来避免 nonce-too-low 错误：

```rust
let mut client = StrikeClient::new(StrikeConfig::bsc_mainnet())
    .with_private_key(&key)
    .build()?;

// Initialize the shared nonce tracker
client.init_nonce_sender().await?;
```

`NonceSender` 会在初始化时从链上获取当前 nonce，之后在本地跟踪。它会区分简单 nonce 漂移与 pending mempool conflict：

- **Nonce 漂移**（例如 `nonce too low`）→ 从链上重新同步并重试一次
- **Pending conflict**（例如 `replacement transaction underpriced` 或 `already known`）→ 从链上重新同步，但不会盲目重试到同一个 nonce lane

该功能通过 `nonce-manager` feature flag 启用，并且默认开启。

简单脚本通常不需要它；它主要面向需要以 tight loop 下单和撤单的 bot。

## 访问内部对象

高级用法中，你可以访问底层 provider 和配置：

```rust
let provider = client.provider();      // &DynProvider — raw alloy provider
let config = client.config();           // &StrikeConfig — addresses and URLs
let addr = client.signer_address();     // Option<Address>
let block = client.block_number().await?;
```

## Sub-Clients

`StrikeClient` 暴露按领域划分的 sub-client：

| 方法 | 返回 | 说明 |
|--------|---------|-------------|
| `client.orders()` | `OrdersClient` | [提交、取消和替换订单](orders.md) |
| `client.vault()` | `VaultClient` | [USDT 授权和余额查询](vault-and-tokens.md) |
| `client.tokens()` | `TokensClient` | [ERC-1155 结果代币操作](vault-and-tokens.md) |
| `client.markets()` | `MarketsClient` | 链上市场状态读取 |
| `client.redeem()` | `RedeemClient` | [结算后代币赎回](vault-and-tokens.md) |
| `client.events()` | `EventStream` | [WSS 事件订阅](events.md) |
| `client.indexer()` | `IndexerClient` | [REST 索引器客户端](indexer.md) |

## 错误处理

所有 SDK 方法都返回 `strike_sdk::Result<T>`，即 `std::result::Result<T, StrikeError>`。

```rust
use strike_sdk::prelude::*;

match client.orders().place(orderbook_market_id, &params).await {
    Ok(orders) => { /* success */ }
    Err(StrikeError::NoWallet) => { /* no private key configured */ }
    Err(StrikeError::Rpc(e)) => { /* RPC transport error */ }
    Err(StrikeError::Contract(msg)) => { /* on-chain revert */ }
    Err(e) => { /* other error */ }
}
```

`StrikeError` variants：

| Variant | 原因 |
|---------|-------|
| `Rpc` | 传输层 RPC 失败 |
| `Contract` | 链上 revert 或 ABI decoding error |
| `NonceMismatch` | 本地 nonce 与链上不一致 |
| `MarketNotActive` | 市场 ID 不是活跃市场 |
| `InsufficientBalance` | USDT 或代币余额不足 |
| `NoWallet` | 未配置私钥却尝试写入操作 |
| `WebSocket` | WSS 连接错误 |
| `Indexer` | 索引器 HTTP 错误 |
| `Config` | 配置无效 |
| `Other` | 通过 `eyre::Report` 包装的其他错误 |
