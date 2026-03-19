# Vault & Outcome Tokens

## USDT Collateral

All trading on Strike uses USDT as collateral. Before placing orders, your wallet must approve the [Vault](../contracts/vault.md) to spend USDT.

### Approve USDT

```rust
// Idempotent — skips if allowance is already sufficient
client.vault().approve_usdt().await?;
```

This calls `USDT.approve(vault, type(uint256).max)`. It checks the current allowance first and skips the transaction if approval is already set. Safe to call every time your bot starts.

### Balance and Allowance

```rust
let signer = client.signer_address().unwrap();

let balance = client.vault().usdt_balance(signer).await?;
println!("USDT balance: {balance}");  // in wei (1 USDT = 1e18)

let allowance = client.vault().usdt_allowance(signer).await?;
println!("vault allowance: {allowance}");
```

You can query any address, not just the signer.

## Outcome Tokens

Strike uses [ERC-1155 outcome tokens](../protocol/outcome-tokens.md) — each market has a YES token ID and a NO token ID. Tokens are minted when [batches clear](../protocol/batch-auctions.md) and can be redeemed after market resolution.

### Token IDs

```rust
let yes_id = client.tokens().yes_token_id(market_id).await?;
let no_id = client.tokens().no_token_id(market_id).await?;
```

### Token Balances

```rust
let signer = client.signer_address().unwrap();

let yes_balance = client.tokens().balance_of(signer, yes_id).await?;
let no_balance = client.tokens().balance_of(signer, no_id).await?;
```

### Token Approval for Selling

To place `SellYes` or `SellNo` [orders](orders.md), the OrderBook must be approved to transfer your outcome tokens:

```rust
let order_book = client.config().addresses.order_book;

// Check if already approved
let approved = client.tokens().is_approved_for_all(signer, order_book).await?;

if !approved {
    client.tokens().set_approval_for_all(order_book, true).await?;
}
```

## Redemption

After a market is [resolved via Pyth oracle](../protocol/oracle-resolution.md), winning outcome tokens can be redeemed 1:1 for USDT. Losing tokens are worthless.

### Check Balances

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

This calls `Redemption.redeem(factoryMarketId, amount)` on-chain.

## Collateral Model Summary

In Strike, 1 YES + 1 NO = 1 USDT (fully collateralized). Both sides of the orderbook lock USDT — askers do NOT need to hold outcome tokens to sell. See [Batch Auctions](../protocol/batch-auctions.md) for details on how collateral flows during clearing.

| Operation | Collateral |
|-----------|-----------|
| Bid at tick T | `lots × T/100 × LOT_SIZE` USDT |
| Ask at tick T | `lots × (100-T)/100 × LOT_SIZE` USDT |
| SellYes | YES tokens custodied by OrderBook |
| SellNo | NO tokens custodied by OrderBook |
| Redeem (winner) | 1 token → 1 USDT |
| Redeem (loser) | worthless |
