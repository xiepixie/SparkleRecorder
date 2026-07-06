# Workflow Page Model And User Flow

Workflow 页面不是“漂亮的图编辑器”。它是把多个简单宏、等待、条件和通知拼成一个可运行自动化的操作台。

## 用户心智模型

用户不是在写 reducer，也不是在管理 lease。他们想表达的是：

- 什么时候开始。
- 先做哪个宏。
- 等到什么画面/文字/状态再继续。
- 成功时走哪条路，失败或超时时走哪条路。
- 多个自动化同时抢鼠标时谁先运行、谁等待。
- 出错后在哪里看证据，下一次怎么修。

因此页面语言应该围绕四个词：开始、执行、等待直到、否则。

## Visual Design Positioning

SparkleRecorder Workflow 是 Pro 级 macOS 原生生产力工具，气质应接近 Xcode、Final Cut Pro、Logic Pro 这类长时间工作的专业软件，而不是 Web dashboard。界面要克制，让自动化数据、依赖关系和运行状态成为视觉焦点。

详细视觉与交互验收标准维护在 [06-workflow-visual-ux-contract.md](06-workflow-visual-ux-contract.md)。本文件只保留用户模型摘要，具体 UI 审查以视觉合同为准。

当前设计决策：Workflow 页面要主动去掉不必要的底色和高饱和大块强调。普通按钮、节点、边列表和工具条不靠 `.controlSurface` 或全宽彩色背景表达“重要”；重要性来自信息层级、位置、hover/focus affordance、语义状态和运行反馈。用户第一眼应该看到自己的宏、条件、依赖、时间轴和证据，而不是一组很吵的控件。

这个原则直接影响交互优先级：Workflow 不是一个右侧表单驱动的配置页，而是一个所见即所得的编排台。用户应该先把左侧或左下角 Macro Library 里的宏拖到中心，再通过画布上的连线和分组理解顺序、条件、否则分支与运行状态；Inspector 只负责精修。

因此，当前任何“先点击按钮，再在右侧面板配置依赖”的路径都只能作为辅助和可访问性路径保留，不能定义产品主体验。Macro Library 应像专业工具里的素材库：宏是素材，Workflow 里的 task 是素材被放入编排后的实例，运行记录是实例每次执行后的证据。

页面的视觉层级也要服务这个心智模型。第一眼应该是“我有哪些任务、它们怎么连、现在跑到哪、哪里失败了”，而不是“这里有很多很醒目的按钮”。普通命令退到工具层，用户数据和运行状态站到前面，这是 Pro 级原生工具和 Web dashboard 的分水岭。

设计约束：

- 避免高饱和度大色块和全宽强底色按钮。
- 不用 `.controlSurface` 这类强制高亮背景来包裹普通节点、边列表或工具按钮；只有真正的危险/确认/正在运行状态才允许短暂强调。
- 默认控件应低对比、轻边界、少填充，融入深色 macOS 窗口氛围。
- 颜色只承担语义：成功、失败、超时、运行中、等待资源；不要用颜色装饰页面。
- UI 应“隐身”：用户第一眼看到的是 workflow 的任务、条件、依赖和运行反馈，而不是组件本身。
- 卡片、按钮、节点不做 Web 风格的 Bootstrap 式大面积色块。

## 页面分区

| Region | Purpose | Owner |
| --- | --- | --- |
| 左侧宏与节点库 | 从 `SavedMacro`、条件、等待、通知、人工确认中创建 task | UI |
| 中央 FlowGraph | 显示任务节点、条件分支、依赖边、运行状态和资源冲突 | UI |
| 下方 Resource Timeline | 显示未来/正在运行/已完成的任务实例，以及前台键鼠占用 | UI |
| 右侧 Inspector | 编辑选中 workflow/task/dependency/run 的参数 | UI |
| 顶部运行控制 | 手动启动、暂停/取消、验证、导入/导出、AI 生成入口 | UI |

## 核心对象

| User Object | Internal Object | Rule |
| --- | --- | --- |
| 宏模板 | `SavedMacro` | 静态素材，不保存运行状态。 |
| 工作流 | `AutomationWorkflow` | 静态图，保存 task 和 dependency。 |
| 任务节点 | `AutomationTask` | 图上的一步，可以引用宏，也可以是条件/等待/通知。 |
| 连线 | `AutomationDependency` | 描述上游 outcome 如何触发下游。 |
| 运行记录 | `AutomationTaskRun` | 每次执行独立生成，不污染宏模板。 |
| 证据 | `RunEvidence` / `evidenceID` | UI 先展示 metadata，按需打开证据。 |

## 必须支持的用户流程

### 1. 所见即所得拖拽编排

用户应该能直接从左侧/左下角的 Macro Library 把录制好的宏拖到中间画布或列表中，生成一个 `AutomationTask`。用户不应必须先点击“添加宏”按钮再去右侧面板配置。

这是 Workflow 页面的主路径。点击添加、右侧 Inspector、快捷按钮都必须保留，但它们是精确编辑和可访问性路径，不应替代“从素材库拖到编排台”的直觉体验。

最低体验：

- 从 Macro Library 拖入画布创建 macro task。
- 从 Macro Library 拖入列表时也能创建 macro task，并清楚显示插入前/后。
- 拖动 task 调整顺序或空间位置。
- 从 task 的连接点拖出依赖线到另一个 task。
- 放开连线后可以选择 trigger：成功、失败、超时、条件满足、条件不满足。
- 右侧 Inspector 是精修入口，不是唯一入口。
- 所有拖拽操作都有键盘/菜单/按钮替代路径，保证可访问性和精确编辑。

Macro Library 的数据边界必须保持清楚：`SavedMacro` 是静态模板，拖入 Workflow 后生成新的 `AutomationTask` 实例；每次运行再生成新的 `AutomationTaskRun` 和 evidence。UI 不允许把 task 的排序、graphPosition、运行结果、失败证据写回宏库模板。

最小直觉要求：用户放手后，节点、预览轨迹、连接线或插入结果应立即稳定出现。不能出现“新建了动作但预览看不到，需要再拖一次/重新定位/刷新才出现”的体验。

验收细节：

- 拖入画布时要有明确落点；拖入列表时要显示插入前/后。
- 任务排序不能因为相同时间、持续时长或条件节点而跳过预期位置。
- 连线创建后，trigger 标签必须直接显示在图上或列表层级中。
- 条件节点不应只是普通卡片并排；至少要通过箭头、缩进、分组或 `If...Then...Else` 面板表达 then/else 关系。
- 用户不打开 Inspector，也能完成“宏 A 成功后跑宏 B；超时后通知我”的基本表达。

### 2. 简单串联

用户把宏 A、等待 1 秒、宏 B 拖到画布，或在列表里调整成：

`A succeeded -> Delay -> B`

验收重点：用户不需要理解 `executionID`，但每次运行会产生独立 `AutomationTaskRun` 链。

### 3. 战斗循环类条件流

用户想表达：

1. 等待战斗结束。
2. 点击屏幕让“离开”按钮出现。
3. 等待“离开”文字出现。
4. 点击离开。
5. 如果 120 秒没有出现，重试或通知。

这要求页面提供：

- OCR 文本条件。
- 区域变化/图标出现/消失条件。
- timeout 分支。
- retry 或 loop 控制。
- 每次失败的截图/文字识别证据。

### 4. 资源冲突等待

如果两个 workflow 都需要前台键鼠：

- UI 应显示一个在运行，一个在等待资源。
- 等待中的任务不应该被用户理解为“失败”。
- 上游延迟完成时，下游预计时间应自动顺延。

### 5. AI 生成工作流

用户可以让 AI 根据宏库生成草稿：

“每天凌晨 3 点运行清理宏，成功后运行上传宏；如果识别不到完成文字就通知我。”

AI 只生成 draft JSON；系统负责 validate、resolve macro、simulate，再导入。

## 节点类型

| Node | User Label | Required Backend State |
| --- | --- | --- |
| Macro | 执行宏 | macroID、resourceRequirement、timeout、retryPolicy |
| Delay | 等待 | duration |
| OCR Text Condition | 等待文本 / 验证文本 | text、matchMode、region、timeout、pollingInterval |
| Visual Condition | 等待画面变化 / 等待图标出现 / 等待图标消失 / 等待颜色 | region/image/pixel spec、timeout、pollingInterval |
| Outcome Condition | 判断上一步结果 | previous outcome predicate |
| Notification | 通知 | title/body/severity |
| Manual Approval | 人工确认 | prompt、timeout、default outcome |

## 连线语义

连线必须显示触发条件，不允许只画一条无语义的线。

| Trigger | Visual Meaning |
| --- | --- |
| success | 绿色实线 |
| failure | 红色实线 |
| timeout | 橙色虚线 |
| cancelled | 灰色虚线 |
| conditionMatched | 绿色条件线 |
| conditionNotMatched | 红色条件线 |
| always | 中性色线 |

合流节点必须有明确 join policy：

- `all`: 所有入边都满足才运行。
- `any`: 任一入边满足就运行。
- `firstMatched`: 第一个满足的入边触发，其他同 execution 的等待分支取消或忽略。

## Visual Dependency Graph

条件和宏不能只是平铺卡片。用户必须能看出“如果...那么...否则...”。

可接受的表达方式：

- 中心画布上的箭头和语义连线。
- 条件节点展开成 `If...Then...Else` 分组面板。
- 列表模式中使用缩进和分组表示条件下游。
- timeout/failure 分支在视觉上和 success 分支不同，但不使用刺眼大色块。
- 连线标签显示 trigger，用户不需要点开 Inspector 才知道这条线何时触发。

## Execution Feedback

Workflow 的魅力在于“看它自己跑”。运行时反馈必须在画布和时间轴上可见。

运行时反馈要像专业剪辑/开发工具的播放头和状态指示：清楚、持续、克制。它不是给 UI 加花，而是让用户确认自动化是否按预期推进。

运行时 UI 规则：

- 当前正在执行的 task 节点有克制的实时反馈，例如细描边呼吸、顶部进度线或小型 activity indicator。
- 不使用大面积高饱和背景来表示运行中。
- 运行反馈应该像 Pro 工具里的播放头、状态灯或进度 hairline：它让用户知道自动化正推进到哪里，但不把整个节点变成动画广告牌。
- 已完成、失败、超时、等待资源应在节点和 timeline 中同时可见。
- 长时间等待条件时显示剩余 timeout 或已等待时长。
- 资源等待应显示“等待鼠标键盘空闲”，而不是内部 lease 状态。
- 运行反馈不能导致节点尺寸跳动或画布布局抖动。

## 用户体验原则

- 页面先让用户完成任务，不优先展示内部字段。
- Pro 级 macOS 原生质感优先，避免 Web dashboard 风格。
- 克制使用颜色和底色，让数据与运行状态成为视觉焦点。
- 普通控件不使用高饱和全宽底色或无必要 `.controlSurface`；只有选中、危险、正在运行、drop target 等语义状态可以短暂加强。
- 拖拽编排是一等路径：宏库拖入、节点拖动、连线创建都应该所见即所得。
- Inspector 是精修入口，不是创建 workflow 的唯一入口。
- 条件节点默认说“等待直到”，而不是暴露 polling。
- 资源冲突说“等待鼠标键盘空闲”，而不是“lease denied”。
- timeout 是用户可见分支，不应藏在失败日志里。
- run history 放在 task/run 详情中，画布只显示摘要。
- UI 不直接调用 Player、scheduler、repository、condition evaluator。
- 所有编辑最终必须变成 reducer action 或 accepted view intent。
