# Current-State Audit

Updated: 2026-08-25

## 1. 审计方法与范围

本审计沿真实用户任务检查当前 SwiftUI 入口、core projection、runtime/reducer 和证据呈现：

1. 找到或创建 workflow。
2. 加入可运行的 macro task。
3. 设定一次或重复计划。
4. 判断任务是否已经启用、下一次何时运行、App 关闭后是否仍会运行。
5. 手动运行并观察进度。
6. 从失败定位到具体 task、原因和证据。
7. 修复后重试并确认结果。

严重度定义：

- **P0 阻断**：用户可能误以为自动化会运行，或无法完成关键恢复动作。
- **P1 高摩擦**：能力存在，但发现、理解或操作成本明显过高。
- **P2 可用性债**：不阻断任务，但持续增加认知负担或降低信任。

## 2. 当前能力事实

| 领域 | 已有能力 | 当前入口/边界 | 判断 |
| --- | --- | --- | --- |
| 计划模型 | task 支持 manual、once、repeating；可计算下一次 occurrence | `AutomationContract.swift`、`AutomationScheduleOccurrence.swift` | core first pass 可用 |
| 计划执行 | runtime tick 驱动 reducer 创建 due run | `AutomationSchedulerClient`、`AutomationRuntimeSession`、`AutomationReducer` | App 进程内 first pass；不是 OS 唤醒 |
| 创建 workflow | 左栏 `+` 直接创建空 workflow | `AutomationWorkflowListView`、`AutomationMainContentView.createWorkflow` | 快，但没有意图引导或启用检查 |
| 设定计划 | task inspector 中手动/一次/重复字段；timeline 可调整下一次计划 | `AutomationTaskInspectorView`、`AutomationResourceTimelineView` | 入口分散，且 task 级语义不易理解 |
| 列表反馈 | workflow 行显示状态和 next schedule | `AutomationWorkflowRow` | 信息过少，无法判断可靠性和最近结果 |
| 运行控制 | task inspector 可发起/取消 run | `AutomationTaskRunControlView` | 控制藏在 task 选择上下文中 |
| 实时刷新 | runtime host 模式每秒刷新 projection | `AutomationOverviewModel` | 有反馈基础，但缺 workflow 级运行叙事 |
| 运行历史 | task inspector 展示最近五次 task runs | `AutomationTaskRunHistoryView` | 以 task 为中心、旧记录隐藏，难回答“一次 workflow 执行发生了什么” |
| 证据 | run 可绑定 evidenceID；宏失败证据、condition evidence、branch evidence 可钻取 | `AutomationTaskRunDetailView` 及 evidence 子视图 | 技术能力较强，但入口深且类型割裂 |
| 后台可靠性 | 文档明确仍缺 OS wakeup、login item、daemon/background session | `../00-current-status.md` | 必须对用户显式说明限制 |

## 3. 现有信息架构

当前页面大致为：

```text
Automation 顶栏（全局状态计数 / AI Draft / Refresh）
├── 左栏
│   ├── Workflows（新建 / 导入 / 导出 / 分享）
│   └── Macro Library / condition sources
├── 中央
│   ├── Canvas（graph + resource timeline）
│   └── Workflow（名称 / 状态 / 数据 / 删除 / task list）
└── Inspector
    ├── workflow / task / dependency 上下文
    ├── task schedule / timeout / retry / resource / condition
    └── task run history → run detail → evidence detail
```

该结构适合已经理解内部模型的专业用户，但三个关键对象没有被清晰分层：

- **Definition**：自动化是什么、包含哪些 task。
- **Activation**：它何时触发、是否具备可靠运行条件。
- **Execution**：某一次实际运行发生了什么。

结果是“编辑”和“运维”被同时塞入 canvas/inspector；用户必须不断改变选择，才能拼出完整答案。

## 4. 关键用户旅程审计

### 4.1 创建与定时设定

当前路径通常是：新建空 workflow → 从 Macro Library 加 task → 在 graph 选 task → 在 Inspector 找 schedule → 选择模式并保存 → 回列表或 timeline 验证 next time。

问题：

| 严重度 | 摩擦点 | 用户后果 |
| --- | --- | --- |
| P1 | “New Workflow”直接产生空对象，没有“我要定时运行一个宏”的快速路径 | 用户先面对画布和内部概念，再理解下一步 |
| P1 | schedule 是 task 属性，但列表以 workflow 为入口；没有解释多 task 各自 schedule 的含义 | 用户不知道是在安排整个流程还是单个步骤 |
| P1 | 常用表达与高级参数混在 task inspector | “每天/工作日/每周”也需要理解 start、interval、unit、end |
| P0 | 缺少统一的启用前检查和 readiness 结论 | 缺 macro、权限、视觉素材或后台能力时仍可能产生“已经设好”的错觉 |
| P0 | App 关闭后不会被 OS 唤醒，但主路径没有把该限制变成计划可靠性提示 | 用户可能错过任务且不知道原因 |
| P2 | next schedule 出现在行、settings 和 timeline，不同入口承担相似编辑/展示职责 | 心智模型不稳定，容易担心修改未生效 |

### 4.2 运行与状态观察

问题：

| 严重度 | 摩擦点 | 用户后果 |
| --- | --- | --- |
| P1 | 手动运行入口依赖 task selection | 用户想“运行这个自动化”，却先要决定从哪个 task 启动 |
| P1 | 顶栏状态计数是系统视角，不是所选 workflow 的叙事 | 无法快速回答“我的任务现在在做什么” |
| P1 | graph、timeline、inspector 分别显示局部状态 | 用户需要自行关联 running task、等待原因和上下游 |
| P1 | waiting for resource/condition、retry、timeout 的动作建议不统一 | 状态可见，但恢复路径不明显 |
| P2 | 每秒 polling 能更新状态，但没有明确的“命令已接受 / 已开始 / 已结束”反馈层级 | 点击运行后仍可能不确定是否生效 |

### 4.3 历史、失败与证据

问题：

| 严重度 | 摩擦点 | 用户后果 |
| --- | --- | --- |
| P1 | history 以 task 为中心并只展示五条，缺少 workflow execution 聚合 | 一次流程跨多个 task 时无法顺序复盘 |
| P1 | evidence 位于 task run detail 深层，且 playback、condition、branch 使用不同展示块 | 用户需先理解证据类型才能找到关键事实 |
| P1 | 失败详情更接近诊断数据，而不是“发生了什么 / 可能原因 / 下一步” | 非开发用户难以恢复 |
| P1 | 没有统一的“修复配置”“重新运行”“从失败点重试”动作模型 | 证据查看与问题解决断开 |
| P2 | legacy latest fallback 对兼容性有价值，但产品上可能弱化“证据属于哪次 run”的信任 | 必须明确标识匹配状态与来源 |

## 5. 根因

1. **后端对象直接映射到 UI**：task/run/evidence 类型成为导航结构，而不是支撑用户目标的实现细节。
2. **缺少 activation/readiness 层**：定义完成不等于可以可靠运行，但 UI 没有专门表达这个差异。
3. **缺少 workflow execution 聚合**：`executionID` 已有基础，但 projection 和主导航仍以单个 task run 为主。
4. **动作与解释分离**：状态和证据组件逐步增加，恢复动作没有同步形成统一合同。
5. **first-pass 状态被过度分散**：next schedule、run status、evidence 在多个面板出现，却没有一个权威摘要。

## 6. 必须保留的优势

- 保留 graph/source-bin 的 Pro 编排路径，不把所有场景强制塞进线性向导。
- 保留 task 级 schedule 语义和多入口启动能力，避免 V1 假装 workflow 只有一个入口。
- 保留 reducer/effect/client 分层，UI 不绕过 action 和 projection。
- 保留 per-run evidenceID、branch/condition evidence 的耐久绑定和 legacy 标识。
- 保留 fixture-first、fake client、Swift Testing 的验收方式。

## 7. 优先级结论

V1 必须先解决信任问题，而不是先美化组件：

1. 明确计划是否真正可运行及 App 在线限制。
2. 给常见任务一个短创建路径，并在提交前展示确定的下一次运行。
3. 建立 workflow execution 级运行中心。
4. 把失败摘要、关键证据和恢复动作放到同一上下文。
5. 最后再扩展高级 schedule、全文检索、证据保留策略和 OS 后台运行。
