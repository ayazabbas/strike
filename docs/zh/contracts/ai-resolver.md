# AIResolver.sol

`AIResolver` 合约管理由 AI 结算的市场。它继承 `FlapAIConsumerBase`，与 FLAP AI 预言机交互，并通过 liveness window 与挑战机制实现乐观结算模式。

## 概览

- 持有在市场创建时存入的 BNB 预言机费用。
- 在市场到期时向 FLAP AI 预言机发送 prompts。
- 接收预言机回调，其中包含 LLM 的二元选择。
- 在最终确认前强制执行 30 分钟 liveness window。
- 支持使用 0.1 BNB bond 发起挑战，并进入 24-hour 管理员 review。

## State

```solidity
mapping(uint256 => uint256) 公开requestToMarket;      // requestId => factoryMarketId
mapping(uint256 => AIMarketConfig) 公开aiMarkets;     // factoryMarketId => config
mapping(uint256 => ProposedResolution) 公开proposals; // factoryMarketId => proposal

uint256 公开constant LIVENESS_PERIOD = 30 minutes;
uint256 公开constant CHALLENGE_PERIOD = 24 hours;
uint256 公开constant CHALLENGE_BOND = 0.1 ether;
uint256 公开constant CHALLENGER_REWARD = 0.01 ether;
```

### AI 市场 Config

```solidity
struct AIMarketConfig {
    string prompt;
    uint8 modelId;
    uint256 oracleFee;  // BNB amount locked at creation
    bool pending;       // true while awaiting oracle callback
}
```

### ProposedResolution

```solidity
struct ProposedResolution {
    uint8 choice;          // 0 = YES, 1 = NO
    uint256 livenessEnd;   // timestamp when liveness expires
    address challenger;    // non-zero if challenged
    uint256 challengeEnd;  // 0 unless challenged
    bool finalized;
}
```

## 函数

| Function | Access | Description |
|----------|--------|-------------|
| `depositFee(uint256 marketId)` | `payable` | MarketFactory 在创建 AI 市场时调用。存储 BNB 预言机费用。 |
| `resolveMarket(uint256 marketId)` | `KEEPER_ROLE` | 使用已存入费用向 FLAP AI 预言机发送 prompt。 |
| `challenge(uint256 marketId)` | `payable` (0.1 BNB) | 在存活窗口内提交 challenge bond，并延长到 24h review。 |
| `finalise(uint256 marketId)` | Anyone | 在无挑战且 liveness window 结束后最终确认结算，并调用 `factory.setResolved()`。 |
| `confirmResolution(uint256 marketId)` | `admin` | 在挑战后确认原始 AI 结果。Bond 进入 treasury。 |
| `overrideResolution(uint256 marketId, bool newOutcome)` | `admin` | 覆盖 AI 结果。挑战者获得 bond 与 0.01 BNB reward。 |
| `withdraw()` | `admin` | 紧急提取 BNB。 |

### Internal（预言机 Callbacks）

| Function | Description |
|----------|-------------|
| `_fulfillReasoning(uint256 requestId, uint8 choice)` | 预言机回调。记录 proposed 结算，并启动 liveness window。 |
| `_onFlapAIRequestRefunded(uint256 requestId)` | 预言机退款回调。重置 pending 标志，使 keeper 可以重试。 |

## 事件

```solidity
event AIResolutionRequested(uint256 indexed marketId, uint256 requestId);
event AIResolutionProposed(uint256 indexed marketId, uint256 requestId, uint8 choice, uint256 livenessEnd);
event AIResolutionChallenged(uint256 indexed marketId, address challenger, uint256 challengeEnd);
event AIResolutionConfirmed(uint256 indexed marketId, uint8 choice);
event AIResolutionOverridden(uint256 indexed marketId, uint8 oldChoice, bool newOutcome);
event AIResolutionRefunded(uint256 indexed marketId, uint256 requestId);
```

## 访问控制

| Role | 授予对象 | 目的 |
|------|-----------|---------|
| `KEEPER_ROLE` | Keeper 钱包 | 在市场到期时调用 `resolveMarket()` |
| MarketFactory 中的 `ADMIN_ROLE` | AIResolver | 通过 factory 调用 `setResolved()` 和 `setResolving()` |
| `admin` (AIResolver) | 部署者 / multisig | 确认或覆盖被挑战的结算 |

## FlapAIConsumerBase Pattern

`AIResolver` 继承自 `FlapAIConsumerBase`，该基类提供：

- `_getFlapAIProvider()` — 返回预言机 provider 地址。
- `reason{value}(modelId, prompt, numChoices)` — 使用 BNB payment 发送 reasoning request。
- `_fulfillReasoning(requestId, choice)` — virtual 回调，由 AIResolver override。
- `_onFlapAIRequestRefunded(requestId)` — virtual 退款回调。

预言机通常会在约 90 seconds 后响应。`_fulfillReasoning` 回调转发约 1M Gas，因此应只执行 storage writes，不应进行 external 调用。
