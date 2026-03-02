# Quick Start

## For Traders

### Web Interface
1. Go to the Strike web app (URL TBD)
2. Connect your wallet (MetaMask, WalletConnect, or Coinbase Wallet)
3. Deposit BNB as collateral
4. Browse active markets and place orders

### Telegram Bot
1. Open [@StrikePriceBot](https://t.me/StrikePriceBot) (TBD)
2. Send `/start` — an embedded wallet is created for you
3. Fund your wallet with BNB
4. Place orders via inline buttons

## For Developers

### Prerequisites
- Node.js 18+
- Foundry ([install](https://getfoundry.sh/))
- BSC testnet BNB ([faucet](https://www.bnbchain.org/en/testnet-faucet))

### Contracts
```bash
cd contracts
forge install
forge build
forge test
```

### Deploy to BSC Testnet
```bash
export DEPLOYER_PRIVATE_KEY=0x_your_key
export BSC_RPC_URL=https://bsc-testnet-rpc.publicnode.com

forge script script/Deploy.s.sol --rpc-url $BSC_RPC_URL --broadcast
```

### Run Keepers
```bash
cd keeper
npm install
cp .env.example .env  # Configure RPC, wallet, contract addresses
npm start
```

### Run Indexer
```bash
cd indexer
npm install
cp .env.example .env
npm start  # REST API on :3001, WebSocket on :3002
```

### Run Frontend
```bash
cd frontend
npm install
cp .env.example .env.local  # Configure contract addresses, indexer URL
npm run dev  # http://localhost:3000
```
