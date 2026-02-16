# Security

## Smart Contract Security

### Reentrancy Protection

All payout functions (`claim()`, `refund()`) use OpenZeppelin's `ReentrancyGuard`. The contracts follow the **Checks-Effects-Interactions** pattern throughout — state is updated before any external calls.

### Access Control

| Function | Access |
|----------|--------|
| `bet()` | Anyone |
| `resolve()` | Anyone (after expiry) |
| `claim()` / `refund()` | Bet holders only |
| `createMarket()` | Keeper or owner |
| `pause()` / `unpause()` | Owner only |
| `withdrawFees()` | Owner only |

### Emergency Controls

- **Pausable**: The owner can pause all betting in case of an emergency
- **24h auto-cancel**: Markets that aren't resolved within 24 hours automatically cancel, allowing refunds
- This prevents funds from being permanently locked

### Anti-Frontrunning

- Betting closes at the **halfway point** of the market duration (2.5 minutes into a 5-minute market)
- This creates a buffer between the last possible bet and the resolution time
- Prevents bots from exploiting price movements visible in the mempool just before expiry

### Fair Outcomes

- **One-sided markets**: If all bets are on the same side, the market cancels and everyone gets refunded
- **Exact ties**: If the resolution price exactly equals the strike price, all bets are refunded
- **Empty markets**: Markets with no bets expire silently — no gas wasted on resolution

### Oracle Security

- Pyth price data is verified **on-chain** — the contract calls `pyth.parsePriceFeedUpdates()`
- Price staleness check: resolution price must be within 60 seconds of the current time
- The Pyth price feed ID is set at initialization and cannot be changed

## Known Limitations

### Custodial Wallets

Privy server wallets are custodial — the bot operator holds the private keys. This is a UX tradeoff for the MVP. Users should only deposit small amounts they're willing to risk.

### Single Keeper

Market creation and resolution depend on the keeper service. If the keeper goes down:
- No new markets are created
- Existing markets can still be resolved by anyone (permissionless)
- Unresolved markets auto-cancel after 24 hours

### Testnet Only

The current deployment is on BSC testnet. Testnet BNB has no real value. Do not send mainnet BNB to testnet addresses.

## Test Coverage

The contract test suite includes 51 tests covering:

| Category | Tests |
|----------|-------|
| Basic betting | ✅ |
| Minimum bet enforcement | ✅ |
| Trading deadline | ✅ |
| Market resolution | ✅ |
| One-sided market refunds | ✅ |
| Exact price tie refunds | ✅ |
| Payout calculation | ✅ |
| Protocol fee deduction | ✅ |
| Reentrancy protection | ✅ |
| Emergency pause | ✅ |
| Auto-cancel after 24h | ✅ |
| Early bird multiplier | ✅ |
| Multi-user scenarios | ✅ |
| Factory clone deployment | ✅ |
