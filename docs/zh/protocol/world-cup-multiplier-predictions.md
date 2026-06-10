# 倍数预测协议

Strike 倍数预测是固定倍率、精确结果预测产品，用于 2026 世界杯等事件系列。本页说明协议行为、经济模型、覆盖、结算、API 与金库职责。

用户指南见[倍数预测](../getting-started/world-cup-multiplier-predictions.md)。线上入口：[strike.fun/world-cup-multiplier-predictions](https://strike.fun/world-cup-multiplier-predictions)。

## 事件与票据模型

每个倍数预测事件都有管理员配置的结果。结果代表支持事件系列中客观可结算的字段，例如比分、胜者、小组赛结果或其他明确事件结果。每个可选结果都有指定倍率。

当前产品提交预测票据。一个票据包含一个或多个 leg，每个 leg 引用一个事件结果。票据可以跨多个事件。组合倍率等于所有 leg 倍率相乘。结算为全有或全无：每个 leg 都必须正确，票据才会获胜。

为了兼容金库，跨事件票据在后端/索引器记账中表示为合成金库事件。API 和金库检查仍然是接受金额、覆盖、结算、领取和退款状态的权威来源。

## 资金池与经济模型

倍数预测使用两个资金池：

- **预测奖池** — 来自已接受的用户预测金额。
- **预测流动性池** — 来自用户贡献；贡献者可能从预测奖池剩余奖励中获益，同时提供赔付覆盖。

当前产品经济模型：

- 预测奖池剩余部分 100% 分配给预测流动性池贡献者。
- 预测奖池剩余部分 0% 平台 reserve 或抽成。
- 本产品方向下，预测金额、 winnings 和贡献者奖励均为 0% fee。

如果没有预测获胜，或者获胜预测没有用完整个预测奖池，剩余预测奖池会按比例分配给预测流动性池贡献者。如果获胜赔付超过预测奖池，预测流动性池可以用于补足已接受票据的差额。

## 覆盖

在请求报价前，前端会估算当前预测流动性池是否可以支持所选倍率和入场金额。如果覆盖额度看起来不足，界面可能会显示降低后的最大入场金额。

该预检查只是客户端估算。API 报价和金库交易检查才是接受金额和覆盖限制的权威来源。如果覆盖已耗尽，报价可能降低接受金额或拒绝票据。前端不应暗示预览赔付在报价/金库接受前一定成立。

覆盖检查应考虑：

- 所选 legs 与组合倍率；
- 请求的入场金额；
- 当前预测奖池和预测流动性池余额；
- 已接受预测敞口；
- 事件状态和提交窗口；
- 金库限制和交易状态。

## 结算与赔付流程

结果数据可用后，每个事件会按配置结果结算。每个票据按全有或全无评估：

- 如果每个票据 leg 都正确，票据有资格获得已接受赔付。
- 如果任一票据 leg 错误，票据不会获得获胜赔付。
- 如果事件被取消或标记为可退款，符合条件的收据可显示退款操作。

结算会确定获胜赔付、预测奖池剩余资金、预测流动性池使用量、贡献者奖励，以及最终领取或退款可用性。

## Earn 与贡献者风险

预测流动性池贡献者可能按比例获得预测奖池剩余资金奖励。贡献也存在下行风险，因为当预测奖池不足时，该池子可以用于覆盖已接受的获胜预测赔付。

贡献者记账必须保持贡献余额、提款、奖励、覆盖义务和结算状态一致。存在活跃敞口或结算待完成时，提款和贡献者奖励可能受限。应用可以显示估算值，但 API 和金库是贡献、提款、领取、退款和结算状态的权威来源。

## API 职责

API 负责向前端和管理界面一致地暴露事件、报价、票据、投资组合、结算和流动性池数据。

当前公开 API routes 包括：

- `GET /v1/world-cup-multiplier/events`
- `GET /v1/world-cup-multiplier/events/{id}`
- `GET|POST /v1/world-cup-multiplier/events/{id}/predictions`
- `GET|POST /v1/world-cup-multiplier/tickets`
- `GET /v1/world-cup-multiplier/tickets/{id}`
- `GET /v1/world-cup-multiplier/portfolio/{wallet}`
- `GET /v1/world-cup-multiplier/backstop-pool`
- `GET|POST /v1/world-cup-multiplier/backstop-pool/contributions`
- `GET|POST /v1/world-cup-multiplier/backstop-pool/withdrawals`

即使部分 legacy API path 仍使用 `backstop-pool`，公开产品文案应称为预测流动性池。

预期 API 行为包括：

- 提供开放和历史倍数预测事件；
- 返回可选结果和配置倍率；
- 报价组合倍率、接受的入场金额和潜在赔付；
- 执行事件状态、时间窗口和覆盖约束；
- 记录已接受预测和票据收据；
- 暴露预测流动性池贡献和提款状态；
- 暴露领取、退款和贡献者奖励可用性；
- 支持管理员结算和事件生命周期操作。

API 响应应明确哪些值是估算值，哪些值已接受或已结算。精确 schema 以生成的 OpenAPI spec 为准。

## 金库职责

金库是 token 移动和已接受链上状态的权威来源。用户操作可能需要先授权 USDT，再提交相关金库交易。

金库职责包括：

- 接受开放事件或票据的预测金额；
- 接受预测流动性池贡献；
- 在交易时执行覆盖和事件状态检查；
- 在结算、领取、退款、提款或贡献者奖励分配前保管资金；
- 支付符合条件的获胜预测领取；
- 处理取消或可退款事件的退款；
- 在结算后分配符合条件的贡献者奖励。

前端和 API 检查应减少失败交易，但金库检查仍然是权威来源。

## 收据与投资组合

投资组合收据应显示倍数预测票据的状态、legs、入场金额、潜在赔付或退款、交易链接，以及可用的领取或退款操作。

贡献者视图应显示预测流动性池贡献状态、估算或已结算奖励、可提款金额，以及与当前敞口相关的风险或覆盖状态。

## 安全与审计参考

当前跨事件票据模型的内部 review 见[World Cup Multiplier Cross-Event Ticket Internal Review](../technical/world-cup-multiplier-predictions-v0-audit.md)。这是内部 Codex-assisted review，不是外部第三方审计。后续 review 已通过此前阻塞的 backend/accounting、synthetic-vault lifecycle、frontend idempotency、smoke-unit、intent-only 和 ticket-privacy 区域。
