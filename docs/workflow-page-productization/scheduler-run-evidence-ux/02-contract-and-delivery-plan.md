# Contract and Delivery Plan

Updated: 2026-08-25

## 1. 合同策略

UX 不能靠 View 临时拼装 repository 和 runtime 数据。实现前应冻结三个纯 core projection 和一组 intents；命名为建议案，未落地前不代表现有 API。

### 1.1 `AutomationWorkflowActivationProjection`

Implementation note (2026-08-25): the first local slice is now accepted as a pure projection derived from `AutomationWorkflowProjection`. It distinguishes empty/blocked, manual-only warning, scheduled-ready, and running states; exposes stable readiness check IDs; and explicitly warns that the App must remain open. Macro availability, permission capability snapshots, paused state, recovery kinds, and entry schedule detail remain future contract extensions.

建议字段：

- `workflowID`
- `state`: unconfigured / blocked / warning / ready / running / paused
- `entrySchedules[]`: taskID、taskName、ruleSummary、nextOccurrence、isEnabled
- `checks[]`: stable ID、severity、title、detail、recoveryKind
- `requiresAppRunning`
- `primaryAction`

规则：readiness 由 core planner 根据 workflow、macro availability 和 adapter 提供的 capability snapshot 组合；UI 不直接检查权限或文件。

### 1.2 `AutomationExecutionSummaryProjection`

建议字段：

- `executionID`
- `workflowID` / workflowName
- trigger source 与 entry task
- aggregate status/outcome
- startedAt/completedAt/duration
- active/waiting task summary
- ordered step summaries
- primary issue 与 permitted actions

聚合排序和 terminal outcome 优先级属于 Owner A。旧 run 缺 executionID 或数据不完整时必须输出 explicit completeness 状态。

### 1.3 `AutomationEvidenceWorkspaceProjection`

建议字段：

- execution/run/task identity
- user-facing issue summary
- key evidence item
- ordered evidence groups
- binding status：exact / legacyFallback / missing / unreadable
- diagnostic disclosure items
- permitted recovery actions

artifact 读取、Open/Reveal 和权限入口仍属于 app adapter；projection 只包含安全 metadata 和 intent capability。

### 1.4 Intents

建议通过 `AutomationViewIntent` 表达：

- create quick workflow draft
- validate activation
- save and enable schedule
- start workflow from resolved entry
- cancel execution
- open workflow/task configuration
- open/reveal evidence artifact
- rerun execution

每个 intent 必须映射为既有 action/effect，或先提交跨 owner 接口请求。禁止在 View 中直接访问 Player、scheduler、repository 或文件系统。

## 2. Owner 边界和接口请求

### Owner C → Owner A：execution/readiness projection

请求内容：

- 定义 activation 状态和阻断优先级；
- 定义多 entry schedule 的权威 next occurrence；
- 按 executionID 聚合 task runs，并冻结 aggregate outcome/ordering；
- 输出 permitted actions，避免 UI 猜测能否 retry/cancel。

验收：pure projection tests 覆盖单入口、多入口、waiting、retry、部分历史、mixed outcomes。

### Owner C → Owner B：capability 与 receipt

请求内容：

- scheduler capability snapshot（仅 App 在线 / 后台能力）；
- permissions、macro/evidence 可用性检查结果；
- start/cancel command receipt 和状态推进；
- evidence artifact metadata 与安全 Open/Reveal client。

验收：fake/sendable clients 覆盖 success、missing、denied、stale、unreadable，不触发真实系统 API。

### Owner A/B → Owner C：accepted contract note

接受后必须同步更新：

- `docs/automation-engine/02-parallel-workstreams.md`；
- 对应 owner workstream；
- 本文件中的实际类型名和状态；
- direct tests 与 fixture。

## 3. 分阶段实施

### Phase 0：合同与 fixture（先行）

- 冻结 activation、execution summary、evidence workspace projection。
- 建立 ready、blocked、scheduled、running、waiting、failed、legacy/missing evidence fixture。
- 为现有 action 能力建立 permitted-action matrix。

退出条件：projection tests 通过；UI owner 无需读取 raw repository 即可渲染全部目标状态。

### Phase 1：Overview + Quick Schedule

- workflow 行改为 status/reliability/next/latest result 层级。
- 新建提供快速路径和高级路径。
- 增加常用计划 preset、自然语言摘要、明确时区和下一次运行。
- 保存前 readiness，保存后 receipt；显式展示 App 在线限制。

退出条件：fixture 下首次用户可完成单 macro 每日计划；所有阻断项有修复入口。

### Phase 2：Run Center

- 按 execution 聚合 active/history。
- workflow 级 run/cancel 入口与 command receipt。
- graph、timeline、Run Center 共用运行 projection。
- waiting/retry/timeout 提供一致解释。

退出条件：用户无需逐个选 task 即可说明一次 execution 的当前状态和最终结果。

### Phase 3：Evidence Workspace + Recovery

- 失败摘要、关键证据、步骤时间线、诊断 disclosure 合并到一次 run 详情。
- 标识 exact/legacy/missing/unreadable binding。
- 增加 rerun、定位任务设置、Open/Reveal 等允许动作。

退出条件：所有 fixture failure 在两次交互内到达关键证据和一个有效恢复动作。

### Phase 4：可靠后台运行（独立产品项目）

- 评估并选择 NSBackgroundActivityScheduler、login item/LaunchAgent 或其他受支持架构。
- 明确睡眠、登出、App 更新、错过 occurrence 和 catch-up 策略。
- 完成权限、签名、生命周期和 live product evidence。

退出条件：在真实发行环境完成授权的关 App/睡眠/唤醒验收；此前 UI 始终保留 App 在线限制。

## 4. 测试策略

### Core

- schedule preset 到 `AutomationSchedule` 的纯映射；
- next occurrence、时区/DST 边界；
- readiness severity 和 primary issue 选择；
- execution 聚合、排序、terminal outcome、retry attempt；
- evidence key-item 和 binding status 选择。

### Adapter

- fake capability/permission/evidence clients；
- start/cancel receipt 到 `AutomationAction` handoff；
- missing/unreadable artifact 不丢失 report；
- 不等待 wall clock，不触发真实 macOS 权限或文件选择器。

### UI projection

- 所有目标状态 fixture snapshot/audit；
- intent handoff，不直接调用 runtime/repository；
- VoiceOver label、键盘路径、动态日期和 Reduce Motion。

### Live product evidence

- quick-create 全流程录屏；
- blocked readiness 与 App-online warning；
- scheduled idle、active waiting、success、failure；
- exact evidence、legacy fallback、preview unavailable；
- 修复配置后产生新 execution，旧 evidence 保持可访问。

## 5. 数据与迁移

- V1 优先使用现有 workflow/task/run schema，通过 projection 增量交付。
- 若新增 enabled/paused、timezone 或 evidence retention 字段，先写 migration/default 策略；旧 workflow 不可被静默启用。
- rerun 创建新 run/execution，不修改历史证据。
- legacy evidence fallback 只读，UI 必须标明来源，不能写回伪装成 exact binding。

## 6. 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| 将 task schedule 包装成 workflow schedule 后语义失真 | 单入口可简化；多入口必须展开列表并显示起点 |
| readiness 变成慢而脆弱的同步检查 | capability snapshot + 可取消异步 adapter；结果显示时间和 stale 状态 |
| execution 聚合改变 reducer terminal 规则 | Owner A 冻结纯 projection 和测试后再做 UI |
| “重试”绕过依赖/resource 语义 | V1 只允许重新运行已解析起点；失败点续跑暂缓 |
| 证据 UI 读取文件导致层级泄漏 | 只通过 presenter/client，core 传 metadata |
| 视觉改造掩盖后台能力缺失 | P0 warning 常驻，Phase 4 独立验收 |

## 7. 建议的首个实现切片

先做 **Phase 0 + Phase 1 的单入口 fixture slice**：不改持久化，不实现后台唤醒，只加入 activation projection、preset mapper、quick schedule UI 和 App-online warning。该切片最早降低误设风险，同时为 Run Center/Evidence Workspace 建立一致的摘要层。
