# ⚡ Strike — Setup Tasks for Ayaz

## 🔑 Things Only You Can Do

### 1. Create Telegram Bot
1. Open [@BotFather](https://t.me/BotFather) on Telegram
2. Send `/newbot`
3. Name it "Strike" or "Strike Bot"
4. Save the **BOT_TOKEN**

### 2. Set Up Privy Account
1. Go to [privy.io](https://privy.io) and sign up
2. Create a new app
3. Enable **Server Wallets** in the dashboard
4. Get your **APP_ID** and **APP_SECRET**
5. Make sure BSC/BNB Chain is enabled

### 3. Get BSC Testnet BNB
1. Go to [BNB Testnet Faucet](https://www.bnbchain.org/en/testnet-faucet)
2. Get tBNB for your deployer wallet
3. You need ~0.1 tBNB for deployment + market creation

### 4. Create `.env` Files
Copy `.env.example` in both `bot/` and `scripts/` directories and fill in values.

## 🤖 Things Kalawd Can Do (After You Provide Keys)

- [ ] Deploy contracts to BSC testnet
- [ ] Create initial markets (BTC/USD 1h, BNB/USD 4h)
- [ ] Test the Telegram bot end-to-end
- [ ] Set up cron job for market resolution
- [ ] Polish bot messages and UX

## 📊 Current Status

| Component | Status |
|-----------|--------|
| Market.sol | ✅ Complete (51 tests) |
| MarketFactory.sol | ✅ Complete |
| Telegram Bot | ✅ Code complete |
| Admin Scripts | ✅ Complete |
| README | ✅ Complete |
| BSC Deployment | ⏳ Needs keys |
| Bot Testing | ⏳ Needs bot token |
| Market Creation | ⏳ Needs deployment |
