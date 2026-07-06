# Workflow Visual And UX Contract

本文定义 Workflow 页面下一阶段的视觉与交互合同。它不是美术偏好，而是验收标准：UI 是否符合 SparkleRecorder 的产品定位，是否让用户直觉地把简单宏拼成复杂自动化，都按这里检查。

## Contract Snapshot

Workflow 页面下一阶段只按一个产品模型验收：Pro 级 macOS 原生自动化编排台。它不是 Web dashboard，不是由一堆彩色按钮驱动的配置页，也不是把依赖关系藏在右侧表格里的表单编辑器。

四条判断线必须同时成立：

1. 视觉克制：普通控件、节点、边列表、工具条和全宽按钮不使用高饱和大色块，也不靠 `.controlSurface` 强行获得重要性。视觉焦点必须回到用户的 task、dependency、condition、timeline、run evidence。
2. 所见即所得：Macro Library 是 source bin。用户从宏库拖出 `SavedMacro` 到画布或列表后，生成新的 `AutomationTask` 实例；点击按钮和 Inspector 只是辅助路径。
3. 依赖可读：中心区域要能直接表达先后顺序、success/failure/timeout/condition then/else、join policy 和资源等待；不能要求用户打开 Inspector 才知道 workflow 会怎么走。
4. 运行会动：workflow 运行期间，当前 task、触发边、资源等待、条件等待、失败证据入口必须在 graph/timeline/inspector 中同步可见，用细描边、hairline progress、状态点和克制动画表达，不用整卡发光或整块填色。

如果一个实现只能通过右侧面板配置依赖、静止态像一组 Web 大按钮、运行时画布看起来没有推进，那么即使 reducer action 能工作，也不能按产品完成验收。

### Current Design Direction

本轮产品定位明确为 Pro 级 macOS 原生生产力工具，参考气质是 Xcode、Final Cut Pro、Logic Pro，而不是 Web 管理后台。Workflow 页面要把视觉焦点还给用户的自动化数据：宏实例、依赖线、条件分支、资源时间轴、运行证据和当前运行状态。

因此下一轮 UI 不以“让按钮更醒目”为目标，而以“让用户不用读表单就看懂 workflow”为目标：

- 普通全宽按钮、普通节点、普通 edge row、Macro Library row、普通 Inspector 分组不应常驻高饱和底色或 `.controlSurface`。
- Macro Library 的角色是 source bin。用户拖出的是 `SavedMacro` 模板引用，落到 graph/list 后才生成新的 `AutomationTask` 实例。
- 中心 graph/list 是主编排台。依赖方向、trigger、then/else/timeout、join policy 和等待资源原因必须尽量在中心区域直接可读。
- 运行态要让静态画布“活起来”，但只能用克制信号：细描边、hairline progress、状态点、触发边轻强调、timeline 占用条和 evidence 角标。
- 右侧 Inspector 是精修面板和可访问性兜底，不是创建 dependency、理解 condition branch、观察 runtime 的唯一入口。

审查时如果页面第一眼是彩色控件集合，而不是 workflow 数据本身，就判为视觉层级失败。若用户无法从 Macro Library 直接拖入、在图上连线、看到条件分支、运行时看见当前节点推进，就判为交互模型未完成。

### Contract Priority

这份合同优先级高于当前实现里的局部样式习惯。凡是 Workflow 相关 UI 仍把普通全宽按钮、普通节点、普通 edge row、Macro Library row 或普通 Inspector 分组做成高饱和大色块，或者用 `.controlSurface` 常驻强调“这里可以点”，都按待修问题处理。

例外只能来自明确用户状态：选中、drop target、connector target、危险确认、失败/超时、live-running。例外必须在 Owner 2 workstream 的 Visual Exception Log 里说明文件、场景、用户状态和移除计划。没有例外记录时，审查默认要求把普通控件降级为原生、低对比、轻边框或菜单/图标按钮表达。

## Workflow Experience North Star

Workflow 的目标体验不是“用户填完一张复杂配置表”，而是“用户把简单宏拼成自己脑中的自动化形状”。用户应该能像在 Pro 工具里整理素材一样，从 Macro Library 拿出已经录制好的宏，放到中心编排台上，直接拖动、连线、分支、运行和观察。

北极星体验按这个顺序验收：

1. Source bin: Macro Library 是素材库，不是添加按钮面板。`SavedMacro` 保持静态模板身份；拖入 workflow 后才派生 `AutomationTask`；每次运行才产生独立 `AutomationTaskRun` 和 evidence。
2. Direct orchestration: 画布/list 是主操作区。拖入、排序、连接、删除、插入前后、连接 trigger 都应在用户看到的位置直接发生；Inspector 只做精修，不定义主路径。
3. Visual dependency graph: 条件、宏、等待和通知不能只是平铺卡片。中心区域必须通过箭头、缩进、分组或 `If...Then...Else` panel 表达 success、failure、timeout、condition matched/not matched。
4. Execution feedback: 用户按下运行后，画布必须有推进感。当前节点、触发边、等待资源/条件、失败证据入口要同步出现在 graph、timeline 和 inspector。
5. Pro restraint: 页面在静止态不能像高饱和 Web dashboard。普通控件退到背景里，自动化数据和运行状态先于命令按钮。

这条北极星也定义了“不接受”的完成状态：如果用户仍主要靠“点击按钮 -> 右侧 Inspector 配依赖”来搭 workflow，或者运行时只能在右侧文字字段里看到变化，那么这个页面只是过渡壳，不是产品目标态。

## Product Positioning

SparkleRecorder 是 Pro 级 macOS 原生生产力工具，气质应接近 Xcode、Final Cut Pro、Logic Pro 这类可长时间工作的专业软件。Workflow 页面不是 Web dashboard，也不是营销页；它是用户每天盯着自动化数据、依赖关系和运行反馈工作的编排台。

### Design Decision: Pro Native, Not Web Controls

2026-07-06 的产品定调：Workflow UI 必须遵循“极简与克制”。之前那类带 `.controlSurface` 强制高亮背景色的全宽按钮，视觉语言更接近 Web 端 Bootstrap 组件，会打破沉浸式深色 macOS 工具氛围。下一阶段 UI 需要主动去掉不必要的底色和大面积强调，让控件隐身，把注意力还给用户正在编排的自动化数据。

这不是“做得更灰”或“更没存在感”，而是专业工具的层级控制：

- 普通对象：轻边框、轻材质、低对比背景。
- 可操作 affordance：hover、focus、handle、drop indicator 出现即可，不常驻大色块。
- 语义状态：运行、等待、失败、超时、危险操作才允许小面积强调。
- 用户数据：task 名称、连线 trigger、运行状态、证据和时间轴永远比控件更显眼。

### Control Surface Policy

`.controlSurface` 不是 Workflow 的默认视觉语言。它只能用于短暂语义状态或平台控件确实需要的局部表面，不能作为“让按钮更明显”的通用方案。

默认禁用范围：

- 普通全宽添加/编辑按钮。
- Macro Library row 的静止态。
- 普通 task node / condition node 的静止态。
- dependency row、edge label、toolbar action。
- Inspector 中的普通分组容器。

允许范围：

- 当前选中对象的轻微 surface lift。
- drop target、connector target、insertion target 这类短暂交互态。
- destructive confirmation 或真正危险操作的小面积强调。
- live-running 期间的克制状态反馈，例如 hairline、细描边、状态点。

每个保留 `.controlSurface` 或强底色的普通控件都必须写入 Owner 2 的 Visual Exception Log，说明文件、表面、用户状态、保留原因和移除计划。

### Surface Decision Rule

Owner 2 做每个 Workflow 控件时，先按这条顺序决定视觉重量：

1. 这是用户数据或运行状态吗？如果是，允许成为主视觉。
2. 这是当前交互状态吗？例如 selected、hover、drop target、connector target、dangerous confirmation、live-running。如果是，允许短暂强调。
3. 这只是普通命令吗？例如添加、移动、编辑、查看、打开菜单。如果是，默认使用原生低对比按钮、图标按钮、菜单、handle、插入线或轻边框。

普通命令不能通过高饱和背景来伪装成主状态。`.controlSurface`、整块强填色和全宽 CTA 只解决“看起来能点”，但会破坏 Pro 工具里最重要的层级：用户应先看见自动化结构和运行进度，再看见工具。

### Native Surface Hierarchy

Workflow 页面默认应该像一个专业剪辑/开发工具的工作区，而不是一组彩色配置按钮。视觉层级按下面顺序排序：

1. 用户数据：task、dependency、condition、timeline、run/evidence。
2. 当前状态：selected、running、waiting、failed、timeout、drop target。
3. 编辑 affordance：connector handle、insertion line、hover outline、菜单、Inspector 字段。
4. 普通命令：添加、移动、删除、导入/导出、验证、运行控制。

普通命令在静止态不能抢过用户数据。全宽按钮、强底色列表行、整块高亮 task card 和常驻 `.controlSurface` 都会把层级倒过来，让页面看起来像 Web dashboard。Owner 2 必须优先用原生 macOS 的 icon button、菜单、细描边、selection outline、focus ring、drop indicator 和 context action 来表达可操作性。

设计目标：

- UI 隐身，把视觉焦点还给用户的 automation graph、timeline、run history 和 evidence。
- 色彩只承载语义，不做装饰。
- 控件默认克制，选中、危险、正在运行这三类状态才允许更明显的强调。
- 页面密度可以高，但必须有清晰层次、稳定布局和原生 macOS 质感。

### Product Design Record: 2026-07-06

这条记录是后续 UI 审查的硬标准，不是可选建议。

SparkleRecorder Workflow 的目标不是把 macOS App 做成一个深色 Web 面板，而是做成 Pro 级原生生产力工具。Xcode 和 Final Cut Pro 的共同点不是“没有颜色”，而是颜色、材质、边框、动画都让位给用户正在编辑的数据。Workflow 页面也是一样：宏、条件、依赖线、资源时间轴、运行证据是主角，普通操作控件应该退到背景里。

由此得出四条直接决策：

1. 普通全宽按钮、工具行、节点列表和 dependency row 不得默认使用高饱和大色块或 `.controlSurface` 强制高亮。它们看起来像 Web CTA 时，就已经偏离产品定位。
2. Workflow 的主路径必须是所见即所得拖拽编排：从 Macro Library 拖入画布或列表、直接移动节点、从节点连接点拉线创建依赖。点击按钮和 Inspector 是辅助路径。
3. 条件和依赖必须在中心区域可读。用户不打开 Inspector，也应能理解“成功走这里、超时走那里、条件不满足走补救分支”。
4. 运行时反馈必须让画布活起来，但只用克制的实时信号：呼吸描边、hairline progress、状态点、触发边轻微强调。整卡发光、整块填色或大面积动画都不符合本页定位。

当前 Workflow UI 如果仍主要依赖点击按钮和右侧面板来配置依赖关系，只能视为过渡壳；它不能作为最终 Workflow 体验验收。

### Product Positioning Addendum: UI Should Disappear

下一阶段的视觉目标不是“换一套更暗的按钮”，而是把普通 UI 从主视觉里撤下来。SparkleRecorder 的用户在 Workflow 页面里真正关心的是：宏实例、依赖线、条件分支、资源占用、运行进度和失败证据。普通按钮、工具条和列表操作只负责让用户完成动作，不能成为页面最醒目的东西。

因此，Owner 2 处理任何 Workflow 控件时都先问三个问题：

1. 这个视觉重量是在表达用户数据，还是只是在表达“这里可以点”？
2. 这个状态是否真的需要颜色，还是 hover、focus、handle、菜单、插入线、细描边就足够？
3. 用户停止交互后，页面第一眼看到的是 workflow 本身，还是一组高亮控件？

如果答案偏向“控件比数据更亮”，就应降级控件样式，而不是继续叠加强背景。`.controlSurface`、高饱和全宽底色和整块填充只允许服务短暂语义状态：选中、drop target、危险确认、失败/超时或 live-running。普通创建、移动、编辑、连接和查看动作不应靠大色块获得注意力。

这条原则也约束 Workflow 的主交互：真正的编排不是右侧表单驱动，而是所见即所得拖拽。Macro Library 是 source bin，中心画布和列表是编排台，Inspector 是精修面板。用户应该能把一个宏拖进去、把两个节点连起来、看到 then/else 或 timeout 分支、启动后看见当前节点和资源时间轴推进；按钮路径只做辅助和可访问性兜底。

### Style Replacement Matrix

这张表是 Owner 2 做视觉收敛时的直接替换规则。不要只删除颜色后留下没有 affordance 的控件；要把 Web 式“大按钮显眼”替换成 macOS 专业工具常见的状态、handle、菜单和插入线。

| Old Pattern | Why It Fails | Replacement |
| --- | --- | --- |
| 普通全宽按钮使用 `.controlSurface` 或强底色 | 像 Web CTA，抢走 graph/timeline 的主视觉 | 原生 icon/text button、toolbar button、menu 或 disclosure control |
| 普通 task/node 整块高饱和填充 | 把每个节点都变成警报，用户无法分辨真实状态 | 低对比 surface + 轻边框；选中/运行/错误时才加小面积语义 accent |
| dependency row 依赖彩色背景表达类型 | 列表像配置面板，不像可读图谱 | 中性色 row + trigger label + 小色点/线型 |
| drag target 常驻大色块 | 静止态太吵，暗示页面主要是按钮集合 | 拖拽时显示 insertion line、drop outline、connector handle |
| running 状态整卡发光或填色 | 动画盖过数据，并可能造成视觉疲劳 | 细描边呼吸、顶部 hairline progress、小 activity indicator |
| 条件节点和宏节点平铺无差异 | 用户看不出 If/Then/Else 逻辑 | 条件分组、缩进、语义箭头或 then/else panel |

如果某处确实需要保留强背景，必须满足两个条件：它是短暂状态而不是静止态默认样式；并且例外原因记录在 Owner 2 workstream 的视觉例外日志里。

## Visual Restraint Rules

### Must

- 使用轻边框、细描边、subtle material、低对比背景来表达普通节点和工具按钮。
- 用小面积语义色标识 success、failure、timeout、running、waiting。
- 运行中状态优先使用细描边呼吸、顶部进度线、小型 activity indicator 或 timeline progress。
- 保持节点尺寸稳定；hover、选中、运行、错误状态不能导致画布跳动。
- 所有文案和状态标签使用面向用户的语言，例如“等待鼠标键盘空闲”，不是 `lease denied`。

### Must Not

- 不要用高饱和度大色块作为普通按钮、节点、边列表或工具栏的默认背景。
- 不要把普通 Workflow 控件包进 `.controlSurface` 只为了让它更醒目。
- 不要做 Bootstrap 风格的全宽强底色按钮。
- 不要用整块彩色背景表示“这是一个可点击操作”；使用原生按钮、图标、handle、菜单或插入线表达可操作性。
- 不要用颜色装饰页面；颜色必须回答“这个任务现在是什么状态”。
- 不要让运行反馈盖过用户数据，也不要用会分散注意力的大面积动画。

### Allowed Exceptions

只有以下状态可以短暂加强视觉：

| State | Allowed Emphasis |
| --- | --- |
| Selected | 细描边、轻微背景提升、handle 可见 |
| Dangerous action | 小面积红色语义 accent，不用整块红底 |
| Running task | 呼吸描边、进度细线、轻量 activity indicator |
| Failed/timeout | 节点角标、边线语义色、timeline 状态点 |
| Drag target | drop indicator、插入线、连接点高亮 |

### Acceptance Gate

Workflow UI review 要先看静止态截图，再看交互态。静止态如果主要视觉印象是“大块全宽按钮、强底色操作区、Bootstrap 式卡片控件”，即使功能能跑，也不能算通过产品验收。普通控件应退到背景里；用户的 task、dependency、timeline、run evidence 才是页面主角。

允许短暂高亮的只有用户正在操作的位置、当前选中对象、危险确认、drop target 和 live-running 状态。任何为了“显眼”而给普通按钮、节点、边列表或 toolbar action 套 `.controlSurface` 的做法，都需要在 owner 文档里写明例外原因。

UI review 必须附带三种截图或录屏片段：

| Review State | What Must Be Visible | What Must Not Dominate |
| --- | --- | --- |
| Idle workflow | task、dependency、timeline、run/evidence 摘要 | 全宽高亮按钮、大面积彩色操作区 |
| Drag/link interaction | drop indicator、insertion line、connector handle、临时连线 | 持久大色块或会改变布局的 hover 样式 |
| Running workflow | 当前 task、触发边、等待资源/条件、失败证据入口 | 整卡强填色、抢眼动画、graph/timeline 状态矛盾 |

判定规则：

- Idle 不通过时，不进入“只是细节 polish”的讨论；先收敛视觉层级。
- Drag/link 不通过时，不能说 Workflow 已可用；按钮和 Inspector 路径不能替代拖拽编排。
- Running 不通过时，不能说运行体验已完成；Workflow 的核心魅力是用户能看见它自己推进。
- 如果某个普通控件必须临时保留强背景，Owner 2 必须在 workstream 的 Visual Exception Log 里记录文件、表面、原因、状态范围和移除计划。

### Implementation Audit Rules

Owner 2 每次提交 Workflow UI 变化时，必须按下面的顺序自查。这里的重点不是“界面更暗”，而是让专业工具的视觉层级稳定下来。

1. 先看静止态：截图中最显眼的应该是 workflow 数据、节点、连线、时间轴和运行证据，不应该是成片的控件背景。
2. 再看操作态：hover、drag target、selected、running、failed 这些状态可以浮出来，但用户停止操作后必须回到克制状态。
3. 检查 `.controlSurface`：普通全宽按钮、节点列表、dependency row、toolbar action 不允许靠 `.controlSurface` 获得重要性。确实需要保留时，要在 Owner 2 workstream 写明例外原因和替代方案。
4. 检查高饱和色块：绿色、红色、橙色、蓝色只允许做小面积语义 accent、边线、角标、状态点或进度线，不允许铺满普通卡片。
5. 检查原生感：操作应优先使用 macOS 熟悉的 icon button、menu、handle、selection outline、insertion line、popover，而不是 Web CTA 式大按钮。
6. 检查布局稳定性：状态变化、运行反馈、hover、drop indicator 不能改变节点尺寸，不能让 graph 或 timeline 发生跳动。

## Drag And Drop Orchestration

Workflow 的第一体验应该是所见即所得拖拽编排，而不是先点按钮再去右侧表单填字段。

用户不应该觉得自己在“填写一个 workflow 表单”。他们应该觉得自己是在把已经录好的宏和条件块像素材一样摆到编排台上，然后直接把它们连成执行逻辑。

Macro Library 在这个模型里不是一个“添加按钮列表”，而是 Pro 工具里的素材库/source bin。用户从这里拿出已经录好的宏，放到画布、列表或条件分组中，系统派生出新的 task instance。这个过程不能污染 `SavedMacro` 静态模板，也不能把 run history 写回宏库。

### Source Bin Contract

Macro Library 的产品角色等同于 Xcode 的文件导航器或 Final Cut Pro 的素材库：它提供素材，不负责保存运行状态，也不应该表现成一组大色块“添加按钮”。用户拖出的永远是 `SavedMacro` 的引用；放到 Workflow 之后才生成 `AutomationTask` 实例；运行之后才生成 `AutomationTaskRun` 和 evidence。

这条边界直接影响 UI 和数据结构：

- Macro Library row 静止态要克制，拖动时才显示 source affordance。
- Drop 到 graph 时，task 的 `graphPosition` 必须与放手位置一致。
- Drop 到 list 时，插入线和真实 `workflow.tasks` 顺序必须一致。
- 同一个 `SavedMacro` 可以被拖入同一个 workflow 多次，每次都是不同 task instance。
- 同一个 task 被运行多次时，每次都是不同 run instance，不回写到 `SavedMacro`。
- 点击添加、Inspector 添加、快捷按钮添加只能作为辅助路径，不能替代拖拽主路径。

### WYSIWYG Authoring Contract

所见即所得不是“支持拖拽 API”，而是用户看到的预览和最终 mutation 必须一致。Workflow 页面最容易破坏信任的点，是插入线显示在 A 后面但真实插到 A 前面，或者拖入新 task 后画布不显示，必须重新定位才出现。

P0 规则：

- 拖入画布：task 出现在放手位置，`graphPosition` 与视觉落点一致。
- 拖入列表：插入线显示 before/after，真实 `workflow.tasks` 顺序必须完全一致。
- 已有 task 重排：上移/下移和拖拽都按相邻插入语义执行，不能因为同一时间、相同 sort key 或长持续时间 condition 跳过眼前下一项。
- 新建或导入 task：节点、预览轨迹、边标签或列表行必须立即显示，不需要刷新、重新定位或打开 Inspector。
- 连线：用户从 connector handle 拉出的临时线、可落点、最终 dependency 方向和 trigger 标签必须一致。
- 非拖拽路径：每个拖拽操作都要有按钮、菜单或 Inspector 兜底，例如上移/下移、插入前/后、连接到选中 task、删除边。

这些规则优先于内部排序实现。内部可以用时间、graph position、task array order 或 projection index，但用户看到的插入位置必须是最终真相。

目标体验：

1. 用户从左侧或左下角 Macro Library 拖出一个 `SavedMacro`。
2. 放到中心画布或列表后，生成一个 `AutomationTask`。
3. 用户拖动 task 调整空间位置或列表顺序。
4. 用户从节点连接点拖线到另一个节点，建立 `AutomationDependency`。
5. 放开连线时选择 trigger：成功、失败、超时、条件满足、条件不满足、总是。
6. 右侧 Inspector 用于精修 schedule、timeout、retry、condition、dependency delay，不是唯一入口。

交互优先级：

| User Intent | Primary UI | Secondary UI |
| --- | --- | --- |
| 使用已有宏 | 从 Macro Library 拖到 graph/list | 点击添加、菜单、Inspector |
| 改变执行顺序 | 直接拖动节点或列表项，显示插入线 | 上移/下移、插入前/后按钮 |
| 建立依赖 | 从节点连接点拉线到目标节点 | Inspector 选择来源/目标，或“连接到选中任务” |
| 表达条件分支 | 图上语义连线、缩进或 `If...Then...Else` 分组 | Inspector 精修 trigger/timeout/retry |
| 运行时排查 | graph + timeline 同步反馈 | Run detail/evidence inspector |

最低可用标准：

- Macro Library 到画布/list 的拖拽必须可见、可撤销、可预测。
- 拖拽过程中必须显示即将创建 task 的位置或列表插入线。
- 对已有 task 的移动不能依赖模糊排序；同时间或同一层级的节点也必须能精确插入前/后。
- 连线创建必须直接在图上完成；Inspector 可以补充 trigger 细节，但不能成为唯一建依赖的地方。
- 点击添加、键盘移动、上下按钮、菜单动作是辅助路径，不替代拖拽主路径。
- 从 Macro Library 拖入的对象必须是 `SavedMacro` 的 task instance 引用，不得污染宏模板，也不得把运行态写回宏库。
- 用户新建或拖入 task 后，画布/list 必须立即显示可理解的预览状态；不能要求用户重新定位、刷新或打开 Inspector 后才出现轨迹、节点或依赖线。
- 所有“会插到哪里”的提示都必须和真实 mutation 一致；如果插入线显示在选中项之后，最终 task 顺序也必须在该项之后。
- 已有 task 的上下移动和列表重排必须按相邻插入语义执行；不能因为同一时间、长持续时间条件、或排序 key 相同而跳过用户眼前的下一项。

拖拽编排的验收要从用户意图出发，而不是从内部 action 出发：

| User Sees | System Must Do |
| --- | --- |
| 从 Macro Library 拖出宏 | 创建一个引用 `SavedMacro` 的 `AutomationTask`，不改写宏模板本身。 |
| 拖到画布空白处 | task 出现在用户放手的位置，graphPosition 持久化到 workflow。 |
| 拖到列表两项之间 | 明确插入前/后，真实排序必须和插入线一致。 |
| 从节点连接点拉线 | 显示临时连线和可连接目标，不要求打开 Inspector。 |
| 放到目标节点 | 创建 dependency，并让用户选择或确认 trigger。 |
| 运行中观察画布 | 当前节点、已触发边、等待资源/条件状态要直接可见。 |

可访问性要求：

- 每个拖拽操作都必须有按钮、菜单或 Inspector 替代路径。
- 节点上下移动、插入前/后、连接到选中节点、删除连线都应能用非拖拽方式完成。
- 拖拽期间必须显示明确 drop indicator；用户能看懂“会插到哪里”。

## Visual Dependency Graph

条件和宏不能只是平铺卡片。用户必须能从画布上看出“如果...那么...否则...”。

Workflow 的核心价值不是“把卡片排成列表”，而是把简单宏拼成用户脑中的流程。条件、失败分支、超时分支和重试不能只藏在右侧表格字段里。

条件节点的视觉目标是减少用户脑内翻译成本。用户看到一个 OCR/视觉判断节点时，应该先看到“等待直到/验证是否/否则”，而不是先看到内部字段。条件、宏、通知可以使用同一套节点语言，但条件必须有明显的分支 affordance：then/else 标签、缩进分组、箭头方向或 If panel。

当前页面如果把 Condition 和 Macro 都显示成并排卡片，再把真实关系藏到右侧面板，就不符合 Workflow 的产品模型。用户必须能在中心区域直接读出执行逻辑：A 成功后去 B，A 超时后去 C，OCR 满足后继续，否则重试或通知。

允许的表达方式：

- 中心画布使用箭头和语义连线。
- 条件节点展开成 `If...Then...Else` 分组面板。
- 列表模式使用缩进、分组和插入线表达条件下游。
- 连线标签直接显示 trigger，不要求用户打开 Inspector 才能理解。
- timeout/failure 分支和 success 分支视觉不同，但不使用刺眼大色块。

依赖线最低要求：

| Trigger | Visual |
| --- | --- |
| success | 绿色小面积 accent / 实线 |
| failure | 红色小面积 accent / 实线 |
| timeout | 橙色小面积 accent / 虚线 |
| cancelled | 灰色虚线 |
| conditionMatched | 绿色条件线 |
| conditionNotMatched | 红色条件线 |
| always | 中性色线 |

条件节点验收：

- 条件节点要回答“等到什么才继续”和“否则去哪里”，不能只显示内部 condition 类型。
- 条件下游至少有一个直观 then/else 表达：语义连线、缩进分组、或完整 `If...Then...Else` panel。
- 条件、宏和通知可以共处一张图，但视觉层级必须让用户看出谁是判断点、谁是执行动作、谁是补救动作。
- 失败、超时和 conditionNotMatched 分支应保留低饱和语义色，不用整块红/橙背景。

依赖表达不能继续停留在“右侧表格配置关系”的产品模型。右侧 Inspector 可以精修 delay、trigger、retry、timeout，但中心区域必须独立表达这些最小语义：

- 先后顺序：箭头方向或列表缩进能看出 A 后 B。
- 条件分支：success/timeout/failure/conditionMatched/conditionNotMatched 至少有标签或分组。
- 合流策略：多个上游指向同一节点时，UI 必须显示 all/any/firstMatched 的用户语言。
- 资源冲突：需要前台键鼠的任务在同一时间竞争时，timeline 必须解释谁在运行、谁在等待。

### Dependency Readability Levels

Workflow 依赖表达按下面三个等级推进。Owner 2 可以分阶段实现，但不能把 Level 1 之前的页面标为可用产品。

| Level | Required Capability | Product Meaning |
| --- | --- | --- |
| Level 0: visible labels | 每条边有方向、trigger label、delay summary | 用户知道 A 后面为什么去 B。 |
| Level 1: direct graph editing | connector handle 拉线创建依赖，删除/改 trigger 不必只靠 Inspector | 用户能直接在图上编排。 |
| Level 2: condition grouping | 条件节点用缩进、箭头或 `If...Then...Else` panel 表达 then/else/timeout | 用户能一眼读出分支结构。 |

当前如果只有平铺卡片加右侧依赖表，最多是过渡壳，不能作为 Workflow 页面目标态。

## Execution Feedback

Workflow 最大的产品魅力是“看它自己跑”。运行时反馈必须让静态画布活起来，但不能变成喧宾夺主的动画秀。

运行态不是装饰；它必须回答用户最关心的三个问题：现在跑到哪里了、为什么还没继续、失败后证据在哪里。

运行反馈是 Workflow 从“静态配置页”变成“自动化控制台”的关键。用户启动 workflow 后，中心画布、资源时间轴和 inspector 不能像死页面一样只显示旧字段；它们必须共同展示当前 task、正在等待的条件/资源、已经触发的边、失败或超时证据入口。

运行态 UI 的基本承诺是：用户按下运行之后，画布必须表现出“自动化正在推进”。这可以是当前 task 的呼吸描边、顶部 hairline progress、触发边的短暂强调、timeline 中的资源占用条，或失败 evidence 的角标；不能只是右侧文字字段变化。

运行时必须可见：

- 当前正在执行的 task。
- 正在等待上游、等待资源、等待 OCR/视觉条件的 task。
- 已完成、失败、超时、取消的 task。
- 资源时间轴中的 foreground input lease 占用和等待队列。
- 长时间条件等待的已等待时长或剩余 timeout。

运行反馈要同时服务 graph 和 timeline：

- Graph 回答“现在跑到哪个节点、接下来会走哪条边”。
- Timeline 回答“什么时候开始、占用了哪个资源、为什么延后”。
- Inspector/Run detail 回答“失败证据在哪里、下一次怎么修”。

推荐表现：

- 当前节点：细描边呼吸或顶部进度线。
- Timeline：running item 用进度线，waiting item 用轻量状态点。
- Dependency：已触发的边线可轻微点亮，未触发分支保持低对比。
- Evidence：失败/超时节点显示证据可用角标，点击后再打开详情。

禁止表现：

- 用大面积高饱和背景表示运行中。
- 运行反馈导致节点变宽、变高或重新排版。
- 在 SwiftUI view 中为了展示状态重新推导 DAG、resource queue 或 scheduler semantics。
- graph、timeline、inspector 各自猜状态，导致同一 task 在不同区域显示不同结果。

运行时反馈必须是数据驱动的 projection，而不是 SwiftUI 临时猜测。Graph、timeline 和 inspector 看到的状态必须来自同一份 runtime projection：同一个 task 不能在 graph 上显示 running、timeline 上显示 idle、inspector 里显示 failed。

当前可消费的 runtime feedback projection first pass 包括：

- `AutomationTaskNodeProjection.timeoutCountdown` 和 `AutomationResourceTimelineItem.timeoutCountdown`：用于渲染剩余时间、deadline、elapsed fraction。
- `AutomationTaskNodeProjection.retryAttemptSummary` 和 `AutomationResourceTimelineItem.retryAttemptSummary`：用于渲染第几次尝试、最大尝试次数、剩余尝试和下一次 retry 时间。
- `AutomationDisplayStatus` / `statusDetail`：用于 graph、timeline、inspector 共享用户语言的运行状态。

UI 可以先用这些字段完成克制的运行态反馈：细描边、hairline progress、状态 chip、下一次 retry 文案。不要在 SwiftUI 中重新扫描 run history 计算 attempt，也不要在 view 里重算 timeout deadline。

### Runtime Feedback Minimum Shape

运行态第一版至少要覆盖三种画面，而不是只在右侧文字里变化：

| Surface | Must Show | Preferred Visual |
| --- | --- | --- |
| FlowGraph node | 当前执行、等待资源、等待条件、失败/超时 | 细描边、顶部 hairline、compact status chip、证据角标 |
| Dependency edge | 已触发边、未走分支、timeout/failure 分支 | 低饱和线型变化、短暂轻强调、trigger label |
| Resource Timeline | foreground input lease、等待队列、延后原因 | 时间条、状态点、等待原因、剩余/已等待时间 |

运行态反馈必须使用同一份 projection。Graph 说“正在执行”、timeline 说“等待”、inspector 说“失败”的状态冲突，视为功能 bug，不是视觉小问题。

首批运行态语言：

| Internal State | User Wording |
| --- | --- |
| queued/planned | 已计划 |
| waitingForDependencies | 等待上一步完成 |
| waitingForResource | 等待鼠标键盘空闲 |
| running macro | 正在执行宏 |
| waiting condition | 等待条件满足 |
| succeeded | 已完成 |
| failed | 失败 |
| timedOut | 超时 |
| cancelled | 已取消 |

## Workflow Page Layout Intent

| Region | Product Role | Interaction Priority |
| --- | --- | --- |
| Macro Library | 用户的素材库，从录制宏创建 task | Drag into graph/list first, button/menu second |
| Center FlowGraph | 主要编排画布，表达 task、condition、dependency、runtime state | Drag, connect, select, inspect |
| Resource Timeline | 解释时间、排队、冲突和运行实例 | Read runtime truth; no hidden scheduler logic |
| Inspector | 精修选中对象参数 | Edit details; not the only creation path |
| Top Toolbar | 运行、验证、导入/导出、AI 草稿入口 | Quiet icon/text controls; no saturated blocks |

## Review Checklist For UI Changes

UI PR 或实现切片必须回答：

- 静止态是否像 Pro macOS 原生生产力工具，而不是 Web dashboard 或 Bootstrap 控件集合？
- 用户能否不打开 Inspector 就完成最基础的拖入、排序、连线？
- 当前 drop target 是否清楚，插入前/后是否和真实结果一致？
- 条件分支是否能一眼看出 then/else 或 success/timeout？
- 运行中、等待资源、失败、超时是否能在 graph 和 timeline 同时理解？
- 普通控件是否避免了 `.controlSurface`、高饱和全宽底色和 Web 风格块状按钮？
- 大量节点/连线时，边线是否通过 Canvas 或 projection 批量绘制，而不是每条线一个复杂 View？
- SwiftUI 是否只渲染 projection 并发出 action/view intent，没有直接调用 Player、scheduler、repository、condition evaluator？
