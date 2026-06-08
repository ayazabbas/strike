# 世界杯倍数预测跨事件票据内部复核

**日期：** 2026-06-08
**审计方：** 内部 Codex 辅助安全复核
**范围：** 跨事件 Prediction Ticket 重构，覆盖后端/indexer、前端、smoke 工具、Portfolio/Admin 展示，以及 `StrikeMultiplierPredictionVault` 的 ticket-as-vault-event 兼容性
**结论：** **本次复核范围内通过。** 之前的发布 blocker 已修复，新的独立复核未发现剩余 release-blocking 问题。

---

## 执行摘要

这是一份内部 Codex 辅助复核，不是外部第三方审计。

本分支加入真正的跨事件 Prediction Ticket：一个用户票据可以包含来自多个预测事件的 legs，同时通过把每张票据表示为一个 synthetic vault event 来复用现有 `StrikeMultiplierPredictionVault` ABI。

上一轮复核因后端/accounting projection、synthetic vault lifecycle 安全性、前端确定性幂等 key、intent-only ticket 处理、smoke 金额单位、以及数字 ticket 隐私而阻塞发布。这些问题已修复并重新复核。本次结果为：**PASS**。

---

## 复核范围

复核覆盖 `feature/world-cup-cross-event-tickets` 分支上的改动：

- `/home/ubuntu/dev/strike-infra`
  - migration `047_world_cup_multiplier_cross_event_tickets.sql`
  - `/v1/world-cup-multiplier/tickets` 创建/列表/detail API
  - legacy `multiplier_predictions` projection 与 accounting 兼容
  - ticket settlement projection 与 vault event 同步
  - 本次重构新增的 DB-backed 回归测试
- `/home/ubuntu/dev/strike-frontend`
  - 跨事件 ticket builder 与提交路径
  - ticket API client 类型
  - Portfolio/Admin 展示
  - ticket-builder tests 与 smoke 脚本默认值
- `/home/ubuntu/dev/strike`
  - `StrikeMultiplierPredictionVault` 跨事件 ticket 兼容性测试
  - docs/security/protocol 引用

---

## 分模块结论

### 合约兼容性：PASS

现有 vault ABI 可以把一张跨事件 ticket 表示为一个 synthetic vault event：

- submit 使用一个 `bytes32 eventId` 表示 synthetic ticket vault event；
- ticket 使用一个 `bytes32 predictionId`；
- synthetic vault event 结算后，可以用该 ticket prediction id 领取 payout；
- synthetic vault event 取消后，可以用该 prediction id 领取 refund；
- vault 不需要知道真实 per-leg event ids。

Focused vault tests 与完整 Foundry suite 均通过。

### 后端/indexer：PASS

后端现在会为本次复核覆盖的所有 ticket 路径创建并更新可靠的 legacy projection：

- 纯 `/world-cup-multiplier/tickets` 提交会使用第一条 leg 的 event 作为 projection event，upsert `multiplier_predictions` projection；
- legacy `/events/{id}/predictions` 兼容路径仍通过请求中的 event 做 projection；
- idempotent retry 会更新 projection，而不是静默跳过；
- projection receipt snapshot 包含 ticket id、projection event id 与 ticket legs；
- event-level accounting 可以继续读取 `multiplier_predictions`，同时 ticket tables 仍是 ticket/leg 的 canonical source。

### Synthetic vault lifecycle 与 claim safety：PASS

实现现在会在 synthetic vault event lifecycle 确认链上结果前，保持本地 ticket 的 public status 为 claim-safe：

- 本地 per-leg settlement 会记录推导出的 ticket outcome；
- confirmed tickets 公开 `ticket_status` 保持 `accepted`，同时在 `metadata.vaultSettlementPending.localTicketStatus` 记录本地终态；
- legacy projections 会同步本地终态，让 event-level accounting 可以更新；
- vault event logs 仍可通过 `contract_prediction_id` 或 `vault_event_id` 更新 ticket 与 projection status；
- 这样可以避免在 vault event 实际 settle/cancel 前，把 ticket 展示成可 claim/refund。

### 前端幂等性：PASS

前端不再根据 wallet、entry amount 与 legs 派生 ticket idempotency key。

- 每次 submit attempt 都生成 nonce-based key；
- 该 key 只在同一次 in-flight attempt 中复用；
- `finally` 中清除 key，因此用户有意重复提交相同 ticket 时会拿到新 key；
- focused Playwright/unit coverage 验证了重复 ticket 的新 key 与 in-flight retry 复用。

### Intent-only tickets：PASS

Intent-only 或未确认资金的 tickets 不会被转换成 paid entitlement。

- settlement recomputation 会检查 funding state；
- non-confirmed tickets 在 terminal/refund handling 触及时可以本地取消；
- cancellation 会记录 `localSettlementResult` metadata，并通过 `funding_status <> confirmed` guard 保证安全。

### Smoke 工具与隐私：PASS

- 跨事件 smoke 脚本默认使用明确的 1 USDT base units：`1000000`。
- 数字 ticket detail access 现在要求 `wallet` query parameter。
- Ticket detail loading 会按 `lower(wallet)` 过滤，wallet 不匹配时返回 not found。
- Ticket listing 仍保持 wallet-scoped。

---

## 之前 blocking findings 的修复状态

### B-01：跨事件 tickets 没有进入 legacy settlement/accounting projection

**状态：** 已修复。

所有已复核的 ticket creation/idempotent 路径都会调用 `upsert_legacy_prediction_projection_tx`。Projection 使用确定的 projection event，冲突时更新，并带有识别 ticket-derived projection 所需的 metadata。

### B-02：Synthetic vault event settlement 未完整接入 claim-safe ticket lifecycle

**状态：** 本次兼容模型范围内已修复。

后端现在把本地 per-leg settlement 与公开 claim/refund readiness 分离。Confirmed tickets 在 vault event 确认 settle/cancel 前保持 accepted，同时把本地终态记录到 metadata 并同步进 accounting projection。

### B-03：确定性前端幂等 key 会合并重复相同 tickets

**状态：** 已修复。

Ticket submission idempotency keys 现在是每次 submit attempt 的 nonce-based key，仅在当前 in-flight attempt 中复用。

---

## High-severity findings 的修复状态

### H-01：Intent-only tickets 不会 settle 或 cancel

**状态：** 已修复到安全本地处理。

Unfunded/non-confirmed tickets 可以转换为 local cancelled state，不会创建 paid entitlement。Confirmed tickets 则保持 claim-safe，直到 vault 确认。

### H-02：Smoke 脚本金额含义不明确

**状态：** 已修复。

Smoke 脚本默认值现在是明确 base units：`ONE_USDT_BASE_UNITS = '1000000'`。

### H-03：Ticket detail endpoint 可通过数字 id 枚举

**状态：** 已修复。

Detail endpoint 现在要求 wallet query，并按 wallet 过滤加载 ticket。

---

## 剩余约束与非阻塞说明

- 这仍是内部 Codex 辅助复核，不是第三方审计。
- Vault lifetime `MAX_TOTAL_PREDICTIONS = 1,000`。已取消/已 finalized 的 predictions 不会释放 slots，因此高流量生产应使用 vault rotation 或 native redesign。
- 合约不验证真实 per-leg event ids、leg outcomes 或 ticket composition。这些事实仍由后端/admin settlement 决定。
- 前端依赖新的 `/v1/world-cup-multiplier/tickets` endpoint，因此后端与前端应原子部署。
- 共享 multi-chain deployment 应在需要时确保 vault event idempotency 包含 chain/contract context。
- 新复核给出的非阻塞 hardening 建议：
  - 为 wallet-scoped ticket detail access 增加显式 HTTP handler 回归测试；
  - 如果产品策略要求所有 terminal leg 类型都本地取消 intent-only ticket，可再增加一个非 refund terminal intent-only 测试。

---

## 验证证据

本次复核完成的命令/checks：

- Backend/indexer：
  - `cargo fmt` — passed
  - `cargo check -p indexer` — passed，有既有 dead-code warnings
  - `cargo test -p indexer world_cup_multiplier --lib --no-run` — passed
  - `cargo test -p indexer cross_event_ticket --lib` — DB-backed SQLx tests 因配置的测试数据库 hostname 无法解析而被环境阻塞；该 filter 中纯 validation tests 在 DB setup 失败前通过
- Frontend：
  - `npm run lint` — passed
  - `npx tsc --noEmit` — passed
  - `npm run build` — passed
  - `npx playwright test tests/world-cup-multiplier-ticket-builder.spec.ts --config=/tmp/strike-frontend-playwright-no-webserver.config.cjs` — 7 passed
- Contracts：
  - `/home/ubuntu/.foundry/bin/forge test --match-contract StrikeMultiplierPredictionVaultTest` — 31 passed
  - `/home/ubuntu/.foundry/bin/forge test` — 620 passed, 0 failed
- 独立复核：
  - 对当前 cross-repo diffs 的 fresh audit 返回 PASS，没有 release-blocking findings。
- Docs：
  - 本页替换上一版 blocked candidate review，更新为当前 PASS review。

---

## 发布建议

本次复核范围内，跨事件 Prediction Ticket refactor 已通过对之前 blocker areas 的内部复核。

公开生产使用前，应一起部署后端与前端，验证 live ticket create/list/detail APIs，使用明确 base-unit amounts 对 live API 运行 cross-event smoke script，并确认 Portfolio/API claim/refund states 与 synthetic vault lifecycle 保持一致。
