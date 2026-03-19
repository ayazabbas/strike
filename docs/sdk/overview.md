# SDK Overview

The Strike SDK is a Rust crate for programmatic trading on Strike prediction markets. It wraps all on-chain interactions — order placement, collateral management, event streaming, and market reads — into a typed, async API.

## Design Philosophy

The SDK is **on-chain first**. All trading operations go directly to BNB Chain via RPC. Live data (events, balances, market state) comes from a WSS subscription or RPC reads. The [indexer](indexer.md) is available for startup snapshots (fetching all markets, orderbook state), but is never in the critical trading path.

## Features

| Feature | Description |
|---------|-------------|
| Order management | Place, cancel, and replace orders in batch transactions |
| Event streaming | Real-time WSS subscriptions with auto-reconnect |
| Vault & tokens | USDT approval, balance queries, ERC-1155 outcome token operations |
| Indexer client | REST client for market snapshots and orderbook state |
| Nonce manager | Optional `nonce-manager` feature flag for bots sending rapid transactions |

## Feature Flags

```toml
[dependencies]
strike-sdk = "0.1"           # nonce-manager enabled by default
strike-sdk = { version = "0.1", default-features = false }  # disable nonce-manager
```

The `nonce-manager` feature enables `NonceSender`, a local nonce tracker that avoids nonce-too-low errors when sending multiple transactions in quick succession. Enabled by default — disable it if you manage nonces externally.

## Installation

Add to your `Cargo.toml`:

```toml
[dependencies]
strike-sdk = "0.1"
tokio = { version = "1", features = ["full"] }
```

Or via cargo:

```bash
cargo add strike-sdk
```

## Links

- [crates.io/crates/strike-sdk](https://crates.io/crates/strike-sdk)
- [docs.rs/strike-sdk](https://docs.rs/strike-sdk)
- [GitHub](https://github.com/ayazabbas/strike)

## Coming Soon

- TypeScript SDK
- Python SDK

## Next Steps

- [Quick Start](quickstart.md) — connect and place your first order
- [Client Configuration](client.md) — RPC, WSS, and wallet setup
- [Example Bots](examples.md) — runnable examples
