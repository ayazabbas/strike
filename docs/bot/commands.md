# Bot Commands

## User Commands

### `/start`

Creates your embedded wallet and shows the main menu.

**Main menu options:**
- 📊 **Markets** — View active prediction markets
- 💰 **My Bets** — View your betting history and active positions
- 👛 **Wallet** — See your wallet address and balance
- ⚙️ **Settings** — Bot preferences
- ❓ **Help** — How to use Strike

### `/help`

Shows a guide on how to use the bot, including:
- How to fund your wallet
- How to place bets
- How payouts work

### `/wallet`

Shows your wallet address and current BNB balance. Includes a button to copy the address for funding.

### `/markets`

Browse currently active markets. Each market shows:
- Asset pair (BTC/USD)
- Strike price
- Current live price
- UP and DOWN pool sizes
- Time remaining

Tap a market to see details and place a bet.

### `/mybets`

View your active and past bets, including:
- Market and side (UP/DOWN)
- Amount bet
- Status (pending/won/lost/refunded)
- Payout amount (if won)

## Admin Commands

### `/admin`

Admin-only commands (requires matching `ADMIN_TELEGRAM_ID`):

| Subcommand | Description |
|------------|-------------|
| `/admin stats` | Bot statistics (users, bets, markets) |
| `/admin markets` | List all markets with state |
| `/admin create` | Manually create a 5-minute BTC/USD market |

## Inline Keyboard Flow

The bot uses inline keyboards for all interactions. The typical betting flow:

```
/start
  └─ Main Menu
      └─ 📊 Markets
          └─ Select a market
              └─ Market Detail (strike, pools, time left)
                  ├─ UP 0.01 / UP 0.05 / UP 0.1
                  ├─ DOWN 0.01 / DOWN 0.05 / DOWN 0.1
                  └─ UP Custom / DOWN Custom
                      └─ Confirmation
                          └─ Transaction sent → Status update
```
