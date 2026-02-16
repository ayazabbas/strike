# Market Lifecycle

Every Strike market follows this flow from creation to payout.

## Flow Diagram

<figure><img src=".gitbook/assets/market-lifecycle-flow.svg" alt="Market Lifecycle Flow"></figure>

## Timeline (5-minute market)

<figure><img src=".gitbook/assets/market-lifecycle-timeline.svg" alt="Market Timeline"></figure>

## Key Rules

| Rule | Detail |
|------|--------|
| **Minimum bet** | 0.001 BNB |
| **Trading stops** | Halfway through duration (2.5 min for 5-min markets) |
| **Anti-frontrun** | Last 60s before expiry: no bets accepted |
| **Protocol fee** | 3% of the losing pool (winners keep their own bets + winnings minus fee) |
| **One-sided refund** | If all bets are on one side, everyone is refunded |
| **Exact tie refund** | If resolution price = strike price exactly, everyone is refunded |
| **Auto-cancel** | If no one resolves within 24h, market cancels and refunds are available |
| **Early bird bonus** | Earlier bets get up to 2x shares (multiplier decreases linearly to 1x at trading deadline) |
