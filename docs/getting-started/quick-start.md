# Quick Start

## Prerequisites

- Node.js 18+
- Foundry ([install](https://getfoundry.sh/))
- A Telegram Bot Token (from [@BotFather](https://t.me/BotFather))
- A Privy account ([privy.io](https://privy.io))
- BSC testnet BNB ([faucet](https://www.bnbchain.org/en/testnet-faucet))

## 1. Clone the Repository

```bash
git clone https://github.com/ayazabbas/strike.git
cd strike
```

## 2. Deploy Smart Contracts

```bash
cd contracts
forge install
forge build
forge test  # 51 tests should pass
```

Deploy to BSC testnet:

```bash
# Set environment variables
export DEPLOYER_PRIVATE_KEY=0x_your_private_key
export BSC_RPC_URL=https://bsc-testnet-rpc.publicnode.com

forge script script/Deploy.s.sol --rpc-url $BSC_RPC_URL --broadcast
```

Note the deployed MarketFactory address from the output.

## 3. Configure the Bot

```bash
cd bot
npm install
```

Create `.env.local` in the project root:

```env
BOT_TOKEN=your_telegram_bot_token
PRIVY_APP_ID=your_privy_app_id
PRIVY_APP_SECRET=your_privy_app_secret
BSC_RPC_URL=https://bsc-testnet-rpc.publicnode.com
MARKET_FACTORY_ADDRESS=0x_your_deployed_factory
CHAIN_ID=97
DEPLOYER_PRIVATE_KEY=0x_your_deployer_key
ADMIN_TELEGRAM_ID=your_telegram_user_id
```

## 4. Start the Bot

```bash
npm run dev
```

## 5. Start the Keeper

In a separate terminal:

```bash
npm run keeper
```

The keeper automatically creates markets every 5 minutes and resolves expired ones.

## 6. Test It

1. Open your bot on Telegram
2. Send `/start` to create your wallet
3. Fund the wallet with testnet BNB
4. Wait for a market to open
5. Place a bet!

## Running as Services (Production)

For persistent operation, use systemd:

```bash
# Install services
sudo cp strike-bot.service /etc/systemd/user/
sudo cp strike-keeper.service /etc/systemd/user/

# Enable and start
systemctl --user daemon-reload
systemctl --user enable --now strike-bot
systemctl --user enable --now strike-keeper

# Check status
systemctl --user status strike-bot strike-keeper
```
