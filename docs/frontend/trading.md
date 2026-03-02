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
│  Pending Claims: [Claim All]                             │
└─────────────────────────────────────────────────────────┘
```

## Orderbook Visualization

- **Price ladder:** vertical list of ticks, bid volume on left, ask volume on right, color-coded depth bars
- **Depth chart:** cumulative bid/ask volume curves, crossing point = indicative clearing price
- **Spread indicator:** best bid / best ask / spread in cents

## Order Entry

- **Side toggle:** Buy YES (green) / Buy NO (red)
- **Price input:** tick slider (1-99) or numeric input, shows implied probability
- **Amount:** BNB input with available balance shown
- **Order type:** dropdown — Limit, Post-Only, IOC, Batch-Only
- **Submit:** single transaction, status toast tracks confirmation

## Batch Info Bar

- Countdown to next batch clearing
- Current batch ID
- Indicative clearing price (computed client-side from current book state)
- Last clearing price and volume
