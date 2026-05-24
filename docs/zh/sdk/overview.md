# SDK 概览

STRIKE SDK 是用于以程序化方式接入 STRIKE 预测市场的 Rust crate。它将下单、抵押资产管理、事件流和市场读取等链上交互封装为类型化的异步 API。

## 设计理念

SDK 采用 **链上优先** 的设计。所有交易操作都会通过 RPC 直接发送至 BNB 链。实时数据（事件、余额、市场状态）来自 WSS 订阅或 RPC 读取。[索引器](indexer.md) 可用于启动快照，例如获取全部市场、订单簿状态、钱包仓位与赎回 backlog，但它不会处在关键交易路径上。

## 功能

| 功能 | 说明 |
|---------|-------------|
| 订单管理 | 在批量交易中提交、取消和替换订单 |
| 事件流 | 支持自动重连的实时 WSS 订阅 |
| 金库与代币 | USDT 授权、余额查询、结果代币和仓位操作 |
| 链上市场读取 | 市场数量、市场 ID，以及用于 factory 到订单簿元数据映射的 `market_meta(factory_market_id)` |
| 索引器客户端 | 用于市场快照、钱包仓位、赎回 backlog 和订单簿状态的 REST 客户端 |
| Nonce manager | 可选的 `nonce-manager` feature flag，适用于快速发送交易的 bot |

钱包持仓辅助方法会归一化已知的 filled-position 与 redeemable payload schema 漂移，因此集成方可以使用稳定的 accessor，而不必自行解码多个索引器变体。

## 预设配置

使用 `StrikeConfig::bsc_mainnet()` 可获得 BSC 主网默认的 RPC、WSS 和索引器 endpoint。自定义配置请参见[客户端配置](client.md)。

## Feature Flags

```toml
[dependencies]
strike-sdk = "0.2"           # nonce-manager enabled by default
strike-sdk = { version = "0.2", default-features = false }  # disable nonce-manager
```

`nonce-manager` feature 会启用 `NonceSender`，这是一个用于快速发送交易的本地 nonce tracker。它会在简单 nonce 漂移时重新同步并重试，并会保守处理 pending mempool conflict，避免盲目替换重试。该功能默认启用；如果你在外部管理 nonce，可以将其关闭。

## 安装

添加到你的 `Cargo.toml`：

```toml
[dependencies]
strike-sdk = "0.2"
tokio = { version = "1", features = ["full"] }
```

或通过 cargo 安装：

```bash
cargo add strike-sdk
```

## 链接

- [crates.io/crates/STRIKE-SDK](https://crates.io/crates/strike-sdk)
- [docs.rs/strike-sdk](https://docs.rs/strike-sdk)
- [GitHub](https://github.com/ayazabbas/strike)

## 即将推出

- Python SDK

## 后续步骤

- [快速开始](quickstart.md) — 连接并提交你的第一笔订单
- [客户端配置](client.md) — 配置 RPC、WSS 和钱包
- [示例 Bots](examples.md) — 可运行的示例
