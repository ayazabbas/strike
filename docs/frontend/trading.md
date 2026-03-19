# Trading Interface

The trading page (`/market/:id`) is where the action happens.

## Layout

```
┌─────────────────────────────────────────────────────────┐
│  Market Info Bar: BTC/USD | Expiry 4:32 | Batch in 2s   │
├──────────────┬──────────────────────┬───────────────────┤
│              │                      │                   │
│  Order Entry │     Orderbook        │   Trade History   │
│              │   (depth chart +     │   (recent fills)  │
│  Side: YES/NO│    price ladder)     │                   │
│  Price: 0.65 │                      │                   │
│  Amount: 10  │                      │                   │
│  Type: Limit │                      │                   │
│  [Place Order]│                     │                   │
│              │                      │                   │
├──────────────┴──────────────────────┴───────────────────┤
│  Open Orders: tick | side | amount | remaining | [cancel]│
│  (Settlement is automatic — no claim step needed)          │
└─────────────────────────────────────────────────────────┘
```

## Orderbook Visualization

- **Price ladder:** vertical list of ticks, bid volume on left, ask volume on right, color-coded depth bars
- **Depth chart:** cumulative bid/ask volume curves, crossing point = indicative clearing price
- **Spread indicator:** best bid / best ask / spread in cents

## Order Entry

- **Side toggle:** Buy YES (green) / Buy NO (red)
- **Price input:** tick slider (1-99) or numeric input, shows implied probability
- **Amount:** USDT input with available balance shown
- **Order type:** toggle — GoodTilCancel (GTC), GoodTilBatch (GTB)
- **Submit:** single transaction, status toast tracks confirmation

### Market Orders & Slippage

In **market mode**, the frontend places a limit order at a tick derived from the best available price plus a slippage tolerance (default 5%, configurable in the order form). This ensures your order fills at or better than your worst acceptable price.

In **limit mode**, your tick is your exact price protection — the order will only fill at the clearing price if it's at or better than your tick. No separate slippage setting is needed.

In both cases, all fills settle at the batch clearing price, never at a worse price than your tick. See [Batch Auctions](../protocol/batch-auctions.md#price-protection) for details.

## Batch Info Bar

- Countdown to next batch clearing
- Current batch ID
- Indicative clearing price (computed client-side from current book state)
- Last clearing price and volume
