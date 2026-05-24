# Redemption.sol

结算后的代币赎回合约。用户销毁胜出的结果代币，并按 1:1 取回 USDT 抵押资产。

## `redeem(factoryMarketId, amount)`

1. 验证市场处于 `Resolved` 状态。
2. 从 MarketFactory 读取胜出结果（YES 或 NO）。
3. 通过 OutcomeToken 从调用者处销毁 `amount` 胜出结果代币。
4. 通过 `vault.redeemFromPool()` 从市场池支付 `amount * LOT_SIZE` USDT。

## 依赖

- **MarketFactory:** 读取市场状态和结果。
- **OutcomeToken:** 销毁胜出代币（需要 MINTER_ROLE）。
- **金库:** 从市场池支付资金（需要 PROTOCOL_ROLE）。

## 说明

- 只有胜出代币可以赎回，失败方代币没有价值。
- 市场池在 `clearBatch()` 的原子化结算过程中注资。
- 每个 position unit 表示 1 lot = LOT_SIZE (1e16 = $0.01)。
- 对于 `useInternalPositions` 市场（当前 5 分钟市场），赎回使用 internal position balances，而非 ERC-1155 代币。

## 事件

- `Redeemed(uint256 indexed factoryMarketId, address indexed user, uint256 amount, bool outcomeYes)`
