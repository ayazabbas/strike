# Frontend Overview

Strike's web frontend is a trading terminal built with Next.js 15, Tailwind CSS, and shadcn/ui. Dark theme, inspired by Bloomberg and Polymarket.

## Stack

| Component | Technology |
|-----------|-----------|
| Framework | Next.js 15 (App Router) |
| Styling | Tailwind CSS + shadcn/ui |
| Wallet | RainbowKit (MetaMask, WalletConnect, Coinbase Wallet) |
| Chain interaction | wagmi v2 + viem |
| Real-time data | Indexer WebSocket |
| Contract ABIs | Auto-generated from Foundry artifacts |

## Pages

| Page | Route | Description |
|------|-------|-------------|
| Markets | `/` | Active markets with volume, spread, countdown |
| Trading | `/market/:id` | Full orderbook, order entry, trade history |
| Portfolio | `/portfolio` | Positions, P&L, bulk claim/redeem |
| Market Detail | `/market/:id/info` | Resolution details, price chart, lifecycle |

## Key UX Patterns

- **Batch-aware:** countdown timer to next clearing, indicative clearing price computed client-side
- **Transaction toasts:** pending → confirmed → success/error status on all chain interactions
- **Gas guards:** estimated gas shown before confirmation, "insufficient funds" prevention
- **Real-time:** orderbook and trade feed update via WebSocket, no manual refresh needed
- **Mobile-first:** responsive breakpoints, touch-friendly order entry, PWA-ready
