# 前端概览

STRIKE 的 Web 前端是一个使用 Next.js 16、Tailwind CSS 与 shadcn/ui 构建的交易 terminal。界面采用深色主题，灵感来自 Bloomberg 与 Polymarket。

## Stack

| Component | Technology |
|-----------|-----------|
| Framework | Next.js 16 (App Router) |
| Styling | Tailwind CSS + shadcn/ui |
| Wallet | Privy (server-managed wallets, no seed phrases) |
| 链交互 | wagmi v3 + viem v2.45 |
| 实时数据 | 索引器 WebSocket |
| 合约 ABIs | 从 Foundry artifacts 自动生成 |

> **注意：** 用户注册时会获得一个 server-managed wallet。交易签名通过 Privy API 在服务端完成，无需浏览器扩展或 seed phrase。

## Pages

| Page | Route | 说明 |
|------|-------|-------------|
| 市场 | `/` | 展示活跃市场及其 volume、spread、countdown |
| 交易 | `/market/:id` | 完整订单簿、下单区和交易历史 |
| 投资组合 | `/portfolio` | Positions、P&L、bulk claim/redeem |
| 市场详情 | `/market/:id/info` | 结算详情、价格图表和生命周期 |

## 关键 UX 模式

- **Batch-aware:** 到下一次清算的 countdown timer，以及客户端计算的 indicative clearing price
- **Transaction toasts:** 所有链交互都会展示 pending → confirmed → success/error 状态
- **Gas guards:** 确认前展示 estimated Gas，并防止 insufficient funds
- **实时:** 订单簿和交易 feed 通过 WebSocket 更新，无需手动刷新
- **Mobile-first:** responsive breakpoints、touch-friendly 下单区、PWA-ready
