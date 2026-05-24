# 金库与结果代币

## USDT 抵押资产

STRIKE 中所有订单簿交易都使用 USDT 作为抵押资产。下单前，你的钱包必须授权[金库](../contracts/vault.md)花费 USDT。

### 授权 USDT

```rust
// Idempotent — skips if allowance is already sufficient
client.vault().approve_usdt().await?;
```

这会调用 `USDT.approve(vault, type(uint256).max)`。该方法会先检查当前 allowance；如果授权已经足够，就会跳过交易。每次 bot 启动时调用它都是安全的。

### 余额与 Allowance

```rust
let signer = client.signer_address().unwrap();

let balance = client.vault().usdt_balance(signer).await?;
println!("USDT balance: {balance}");  // in wei (1 USDT = 1e18 wei)

let allowance = client.vault().usdt_allowance(signer).await?;
println!("vault allowance: {allowance}");
```

你可以查询任意地址，不限于 signer。

## 结果代币

STRIKE 使用 [ERC-1155 结果代币](../protocol/outcome-tokens.md)。每个市场都有一个 YES 代币 ID 和一个 NO 代币 ID。代币会在 [batch 清算](../protocol/batch-auctions.md)时铸造，并可在市场结算后赎回。

### 代币 ID

```rust
let yes_id = client.tokens().yes_token_id(market_id).await?;
let no_id = client.tokens().no_token_id(market_id).await?;
```

### 代币余额

```rust
let signer = client.signer_address().unwrap();

let yes_balance = client.tokens().balance_of(signer, yes_id).await?;
let no_balance = client.tokens().balance_of(signer, no_id).await?;
```

### 卖出时的代币授权

提交 `SellYes` 或 `SellNo` [订单](orders.md)时，订单簿必须获得转账你结果代币的授权：

```rust
let order_book = client.config().addresses.order_book;

// Check if already approved
let approved = client.tokens().is_approved_for_all(signer, order_book).await?;

if !approved {
    client.tokens().set_approval_for_all(order_book, true).await?;
}
```

## 赎回

市场通过 [Pyth 预言机完成结算](../protocol/oracle-resolution.md)后，获胜结果代币可按每 lot `LOT_SIZE`（$0.01）的比例赎回为 USDT。失败结果代币没有价值。

### 检查余额

```rust
let signer = client.signer_address().unwrap();

// Returns (yes_balance, no_balance)
let (yes, no) = client.redeem().balances(market_id, signer).await?;
println!("YES: {yes}, NO: {no}");
```

### Redeem

```rust
// Redeem winning tokens for USDT
client.redeem().redeem(market_id, amount).await?;
```

这会调用链上的 `Redemption.redeem(factoryMarketId, amount)`。

## 抵押资产模型摘要

每个匹配的 lot 都以 `LOT_SIZE`（$0.01）完全抵押。订单簿两侧都会锁定 USDT；asker 不需要持有结果代币即可卖出。清算期间的抵押资产流程详见[批量拍卖](../protocol/batch-auctions.md)。

| Operation | 抵押资产 |
|-----------|-----------|
| Bid 以 tick T | `lots × T/100 × LOT_SIZE` USDT |
| Ask 以 tick T | `lots × (100-T)/100 × LOT_SIZE` USDT |
| SellYes | 由订单簿托管 YES 代币 |
| SellNo | 由订单簿托管 NO 代币 |
| Redeem (winner) | 1 lot → $0.01 (LOT_SIZE) |
| Redeem (loser) | 无价值 |

> **注意：** 当前市场使用 internal positions，但 ERC-1155 操作可用于未来的市场类型。
