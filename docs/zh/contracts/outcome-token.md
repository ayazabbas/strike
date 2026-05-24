# OutcomeToken.sol

> **注意:** 当前 5 分钟市场使用 internal positions (`useInternalPositions = true`)，不会铸造 ERC-1155 代币。本合约面向未来需要可转让结果代币的市场类型。

用于二元结果代币的 ERC-1155 多代币合约。

## 代币 ID 方案

```
YES token: marketId * 2
NO token:  marketId * 2 + 1
```

该方案是确定性的，不需要额外的 registry 或 mapping。

## 函数

### `mintPair(marketId, amount)`
存入 `amount` 抵押资产，获得 `amount` YES 代币和 `amount` NO 代币。该函数通过金库集成调用，仅协议合约可以调用。

### `burnPair(marketId, amount)`
交回 `amount` YES 代币和 `amount` NO 代币，取回 `amount` 抵押资产。结算前后均可使用。

### `redeem(marketId, amount)`
仅在结算后可用。销毁 `amount` 胜出代币，取回 `amount` 抵押资产。失败方代币没有赎回价值。

## 访问控制

- `mintPair` / `burnPair` / `redeem`: 仅限协议合约调用（金库、订单簿）。
- 标准 ERC-1155 转账: 不受限制，代币可以自由转让。

## 事件

```solidity
event PairMinted(address indexed to, uint256 indexed marketId, uint256 amount);
event PairBurned(address indexed from, uint256 indexed marketId, uint256 amount);
event Redeemed(address indexed from, uint256 indexed marketId, uint256 amount, bool winningOutcome);
```
