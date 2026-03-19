# Placing & Managing Orders

## Concepts

Before placing orders, understand the key parameters:

### Sides

Strike has a [4-sided orderbook](../contracts/orderbook.md). Each side determines what collateral is locked and what you receive on fill.

| Side | What you're doing | Collateral locked | On fill you receive |
|------|-------------------|-------------------|-------------------|
| `Bid` | Buying YES tokens | `lots × tick/100 × LOT_SIZE` USDT | YES tokens |
| `Ask` | Buying NO tokens | `lots × (100-tick)/100 × LOT_SIZE` USDT | NO tokens |
| `SellYes` | Selling YES tokens | YES tokens (custodied by OrderBook) | USDT |
| `SellNo` | Selling NO tokens | NO tokens (custodied by OrderBook) | USDT |

### Ticks

Ticks range from 1–99 and represent the price of a YES token in cents. A bid at tick 70 means you're willing to pay $0.70 for a YES token (implying 70% probability that the price is above strike at expiry).

### Lots

Each lot is `LOT_SIZE = 1e16 wei = $0.01` of collateral. 100 lots at tick 50 locks `100 × 0.50 × $0.01 = $0.50` USDT.

### Order Types

| Type | Behavior |
|------|----------|
| `GoodTilCancelled` (GTC) | Rolls unfilled remainder to the next [batch](../protocol/batch-auctions.md) |
| `GoodTilBatch` (GTB) | Expires at end of current batch if unfilled |

### Price Protection (Slippage)

Your tick **is** your price protection. In a batch auction, all fills in a batch settle at the same uniform clearing price. Your order will never fill at a price worse than your tick — if the clearing price exceeds your limit, your order simply doesn't fill.

This is fundamentally different from AMM slippage. There's no risk of price movement between submission and execution because orders are collected and cleared together. Set your tick to the worst price you're willing to accept.

For example, if the current best ask is at tick 55 and you're comfortable paying up to 60 cents for a YES token, place a bid at tick 60. You'll pay the clearing price (which could be 55, 57, or anything ≤ 60), never more.

## OrderParam Constructors

`OrderParam` has convenience constructors that default to GTC:

```rust
use strike_sdk::prelude::*;

// GTC orders (default)
let bid = OrderParam::bid(50, 100);          // bid at tick 50, 100 lots
let ask = OrderParam::ask(60, 100);          // ask at tick 60, 100 lots
let sell_yes = OrderParam::sell_yes(55, 50); // sell YES at tick 55, 50 lots
let sell_no = OrderParam::sell_no(45, 50);   // sell NO at tick 45, 50 lots

// For GTB orders, use the full constructor
let gtb_bid = OrderParam::new(Side::Bid, OrderType::GoodTilBatch, 50, 100);
```

## Placing Orders

Place one or more orders in a single transaction using `client.orders().place()`:

```rust
let orders = client
    .orders()
    .place(
        market_id,
        &[OrderParam::bid(40, 100), OrderParam::ask(60, 100)],
    )
    .await?;

for o in &orders {
    println!("order {} | {:?} | market {}", o.order_id, o.side, o.market_id);
}
```

This calls `OrderBook.placeOrders()` on-chain. The returned `Vec<PlacedOrder>` contains the order IDs parsed from `OrderPlaced` events in the transaction receipt.

## Cancelling Orders

Cancel one or multiple orders:

```rust
// Cancel multiple
let ids: Vec<_> = orders.iter().map(|o| o.order_id).collect();
client.orders().cancel(&ids).await?;

// Cancel a single order
client.orders().cancel_one(order_id).await?;
```

`cancel()` calls `OrderBook.cancelOrders()` (batch). `cancel_one()` calls `OrderBook.cancelOrder()` (single). Both unlock collateral or return custodied tokens.

## Replacing Orders (Atomic Cancel + Place)

Replace orders atomically — cancel existing orders and place new ones in a single transaction:

```rust
let old_ids = vec![order1.order_id, order2.order_id];
let new_params = vec![OrderParam::bid(45, 100), OrderParam::ask(55, 100)];

let new_orders = client
    .orders()
    .replace(&old_ids, market_id, &new_params)
    .await?;
```

This calls `OrderBook.replaceOrders()`. Net collateral settlement means you only deposit or withdraw the difference — useful for repositioning quotes without freeing and re-locking collateral in separate transactions.

## PlacedOrder

The return type from `place()` and `replace()`:

```rust
pub struct PlacedOrder {
    pub order_id: U256,    // unique on-chain order ID
    pub side: Side,        // Bid, Ask, SellYes, or SellNo
    pub market_id: u64,    // market the order belongs to
}
```

Order IDs are parsed from `OrderPlaced` events emitted in the transaction receipt.

## Selling Outcome Tokens

To sell YES or NO tokens you already hold, use `SellYes`/`SellNo` sides. The OrderBook custodies your tokens when the order is placed, and returns them if the order is cancelled or unfilled.

Before selling, approve the OrderBook to transfer your outcome tokens:

```rust
// Approve OrderBook to transfer your outcome tokens (one-time)
let order_book = client.config().addresses.order_book;
client.tokens().set_approval_for_all(order_book, true).await?;

// Place a sell order
let orders = client
    .orders()
    .place(market_id, &[OrderParam::sell_yes(55, 50)])
    .await?;
```

See [Vault & Outcome Tokens](vault-and-tokens.md) for more on token operations.
