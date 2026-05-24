# 投资组合

投资组合页面（`/portfolio`）展示所有市场中的仓位。

## Sections

### 抵押资产余额
- USDT balance
- Locked（支持 open orders 的抵押资产）
- Available（可提取余额）
- Deposit / Withdraw 按钮

### Active Positions
- 每个市场的 position size
- 使用上一次清算价格计算当前 mark-to-market
- 每个 position 的 unrealized P&L

### Open Orders
- 跨所有市场的全部 open orders
- 单独取消或批量取消
- 按市场、side、状态过滤

### Redeemable
- resolved 市场中的获胜仓位
- "Redeem All" 按钮

### History
- 使用 entry/exit price 展示 completed trades
- Historical P&L chart
- 可按市场与 date range 过滤
