# Engine To UI Contract

本文件是两人协作的主沟通渠道，规定 Engine owner 的能力如何交付给 UI owner。目标是让后端进度能够及时变成前端可开发的 projection/action/fixture，而不是只停在“代码已经有了”。

## 基本规则

- Engine owner 不直接要求 UI 读内部 state。
- UI owner 不在 SwiftUI `body` 中补状态机、DAG 解析、资源仲裁或文件 IO。
- 每个跨 owner 能力必须有请求、接受、测试和样例 projection。
- 后端完成不是“类型存在”，而是前端能通过 projection/action 使用。

## Communication Channels

本阶段只保留两个 owner：

- Owner 1: Engine, Runtime, And AI CLI，工作文件是 [workstreams/engine-runtime-ai.md](workstreams/engine-runtime-ai.md)。
- Owner 2: Product UI And Workflow UX，工作文件是 [workstreams/product-ui-ux.md](workstreams/product-ui-ux.md)。

沟通写法：

1. 跨边界合同写在本文件：新 action、projection 字段、CLI output、fixture、validation warning 都必须先在这里登记。
2. 各自计划写在自己的 workstream 文件：任务清单、风险、实现日志、测试证据写到各自文件。
3. 请求双写但主次明确：请求方在自己的 workstream 记录摘要，完整请求写到本文件；接受方在自己的 workstream 写接受、拒绝或替代方案。
4. 完成状态只在本文件升级：`proposed -> accepted -> implemented -> tested -> ready-for-ui`。没有测试和 fixture 不得标 `ready-for-ui`。
5. 争议不散落聊天记录：未决问题写在本文件的 open questions，解决后移动到 accepted contracts。

## Backend Capability Notice

Engine owner 每完成一个会影响 UI 的能力，必须先在本文件写一条 notice，再同步到自己的 workstream 文件。UI owner 只把 `ready-for-ui` 的 notice 当真实能力接入。

模板：

```md
### Capability: <short name>

- Owner: Engine
- Status: proposed | accepted | implemented | tested | ready-for-ui
- User-facing capability:
- New or changed types:
- New or changed `AutomationAction` / `AutomationEffect`:
- Projection fields UI should read:
- Fixture/example state:
- Tests:
- Migration/backward compatibility:
- Open UI questions:
```

只有状态到 `ready-for-ui`，UI owner 才能把它当成真实能力设计交互。

## Contract Surfaces

| Surface | Owned By | Consumed By | Rule |
| --- | --- | --- | --- |
| Core types | Engine | UI | 保持 Codable/Equatable/Sendable，破坏性迁移必须写迁移说明。 |
| Reducer actions | Engine | UI | UI/provider/scheduler/player 只能通过 accepted action 进入状态机。 |
| Effects | Engine | Engine runtime | Reducer 只描述请求，runtime/adapter 执行真实副作用并回传 action。 |
| Live clients | Engine runtime | UI indirectly | Runtime 不绕过 reducer 改 state，UI 不直接调用 live clients。 |
| Projection | Engine + UI | UI | UI 渲染 projection，不重新实现状态语义。 |
| Persistence/package | Engine | UI/AI importer | UI 只用 accepted codec 和 reducer persistence。 |
| AI draft schema | Engine | CLI/UI | 外部稳定 schema 编译到内部 workflow，不直接等同内部 Codable；本阶段只实现 CLI 接口。 |

## Needed Backend Contracts For Next UI

| Capability | Owner | Needed Contract | UI Depends On |
| --- | --- | --- | --- |
| Repeating schedule occurrence | Engine | 给定 clock tick 创建下一次 run，不重复、不漏跑 | Timeline 能显示下一次/未来多次计划。 |
| Resource wait queue | Engine | resource busy 时进入 waiting queue，可被后续 release 唤醒 | UI 显示“等待鼠标键盘空闲”，而不是失败。 |
| Timeout watchdog | Engine | task timeout 触发 `.timedOut` 并释放资源 | UI 能画 timeout 分支和倒计时。 |
| Retry policy | Engine | terminal failure 后按 policy 创建下一 attempt | UI 能显示尝试次数和下一次重试。 |
| Join policy | Engine | `all` / `any` / `firstMatched` 的 reducer 语义 | FlowGraph 能表达分支合流。 |
| Visual conditions | Engine | regionChanged/imageAppeared/imageDisappeared/pixelMatched spec 和 evaluator result | Inspector 能提供直觉条件。 |
| Workflow draft import | Engine | validate/resolve/compile draft JSON 到 internal workflow | AI 生成入口和 CLI validator/importer 共享。 |
| Simulation | Engine | fake clock + fake outcomes 输出预计 runs/timeline/warnings | UI 导入前预览和错误提示。 |
| CLI result envelope | Engine | stable `sparkle.cli.result.v1` JSON for validate/simulate/import dry-run | UI draft preview 和 AI 代理读取同一套结果。 |

## Frontend Request Protocol

UI owner 如果发现页面需要新字段或动作，不直接改 reducer。按以下流程：

1. 在 [workstreams/product-ui-ux.md](workstreams/product-ui-ux.md) 写 `Interface Request` 摘要。
2. 标明用户场景、现有 projection/action 缺口、期望字段、默认值、失败状态。
3. 在本文件写完整请求，等待 Engine owner 接受、拒绝或提出替代合同。
4. 合同接受后，UI owner 先用 fixture 做 UI，再接 live projection。
5. 合同测试存在后，UI 才能移除临时 fixture guard。

## Status Labels For UI

后端 projection 应优先提供用户语言，而不是让 UI 翻译内部 case：

| Internal | Preferred User Label |
| --- | --- |
| planned | 已计划 |
| waitingForDependencies | 等待上一步 |
| waitingForResource | 等待鼠标键盘空闲 |
| queued | 准备执行 |
| running | 正在执行 |
| completed/succeeded | 已完成 |
| completed/failed | 失败 |
| completed/timedOut | 超时 |
| completed/cancelled | 已取消 |
| resourceConflict | 资源冲突 |
| missingMacro | 缺少宏 |

## Fixture Requirement

每个 ready-for-ui 能力至少提供一个 fixture：

- one happy path。
- one failure or timeout path。
- one conflict or missing-reference path if applicable。

Fixture 可以是 Swift test helper、projection fixture 或 docs JSON，但必须能让 UI owner 在 live 后端不稳定时开发页面。
