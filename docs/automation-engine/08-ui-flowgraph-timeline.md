# SwiftUI FlowGraph And Resource Timeline Workstream

## 目标

提供符合用户直觉的编排 UI，同时保证大规模节点和连线不会拖慢 SwiftUI。

## 用户入口原则

第一入口不要是“复杂 DAG 编辑器”。用户先看到规则式配置：

- 几点运行这个宏。
- 跑完后运行另一个宏。
- 失败时重试或运行告警宏。
- 找不到文本时走另一条。
- 鼠标键盘被占用时排队。

FlowGraph 是高级视图，用于解释和调整。

## UI 结构

```text
AutomationMainView
  Left: workflow/task library
  Center: FlowGraphCanvas
  Right: Inspector for workflow/task/dependency settings
  Lower Right: ResourceTimelineView
```

## FlowGraph 性能策略

- 节点用稳定 ID，不用 `UUID()` in body。
- 节点列表由 view model projection 预先排序。
- 连线用单个 `Canvas` 批量绘制，不为每条边创建 View。
- 拖拽时只更新 transient drag state，落点时才写 reducer action。
- 使用 grid snap，但 snap 只在 `onEnded` 或低频节流时提交。

## Resource Timeline

内部可以有 channel，但 UI 不叫 Channel 0/1。

| Internal | UI Label |
| --- | --- |
| `foregroundInput` | 需要控制鼠标键盘 |
| `none/background` | 后台等待/检测 |
| queued | 正在排队 |
| delayedByDependency | 因上游延迟顺延 |

## 第一版 UI 范围

从只读 projection 进入第一版 authoring：

- 显示 workflow tasks、依赖边、每个 task 的 status、resource timeline。
- 创建 workflow。
- 从 `SavedMacro` 添加 macro task。
- 添加 manual approval / external signal condition task。
- 通过 FlowGraph 节点按钮拉线建立依赖，通过 dependency inspector 删除依赖。
- 通过 FlowGraph 节点和 task inspector 取消 active run。
- 通过 inspector 编辑 workflow/task/dependency 基础字段。
- 通过 task inspector 编辑 schedule、condition source、timeout、polling 和 retry attempts。
- 通过 OCR condition 的 Pick Text Region 从真实屏幕/窗口选中文字并写入 `searchRegion` bounds。
- 通过 OCR condition 的 Draw Region 在屏幕上拖拽任意矩形并写入当前 display/window/content 坐标空间的 `searchRegion` bounds。
- 通过 OCR region editor 预览/微调 bounds，并提示多显示器、window/content 坐标空间是否有可用上下文。
- 通过 `.sparkrec_workflow` 导入/导出/分享 workflow，支持当前 workflow 和全部 workflows package；冲突时让用户选择 Add Copies 或 Replace Existing，引用本地不存在的 macro 时先提示再导入。
- external signal 由 app 内 signal store/toggle 提供，manual approval 由 AppKit approval presenter 提供；SwiftUI 不直接调用 condition evaluator。

当前落地（2026-07-05）：

- `AutomationViewProjection.overview(from:)` 将 `AutomationRunState` 映射成只读 UI projection。
- `AutomationOverviewProjection.ownerCFixture()` 提供静态 fixture，覆盖 scheduled、waiting、running、failed、cancelled、timed out、blocked 等状态。
- `AutomationMainView` 可通过 `AutomationRepositorySnapshotClient` 刷新 live reducer state，并用 `AutomationViewProjection.overview(from:)` 生成 UI projection。
- `AutomationFlowGraphEdgeCanvas` 使用单个 Canvas 绘制依赖边，端点和边状态由 projection 预先计算。
- FlowGraph 节点拖拽只在 gesture transient state 中移动，松手后 grid snap 并发送 `AutomationAction.moveTask`；reducer 持久化 `AutomationTask.graphPosition`。
- FlowGraph 节点可选择、手动运行、取消 active run、启动/完成 dependency link；task inspector 也可对当前 active run 发出 cancel；dependency 选择和删除走 inspector/reducer action。
- `AutomationTaskInspectorView` 可编辑 manual/once/repeating schedule，以及 manual approval、external signal、OCR text、previous outcome condition 参数。
- `AutomationTaskRunHistoryView` 在 task inspector 内展示该 task 最近运行的 outcome reason、Created/Scheduled/Ready/Started/Completed 时间、attempt、execution chain、upstream count、evidence availability 和 duration metadata；SwiftUI 不读取 Player internals 或 evidence payload。
- `AutomationOCRRegionPicker` 复用现有 `TextPickerOverlay`，从上游 macro surface 优先选取目标窗口，写入 OCR text 和 `searchRegion` bounds；有 target surface 时使用 content-normalized region，否则退回 display-absolute region。
- `AutomationOCRRegionPickerOverlay` 支持不依赖 OCR 文本识别的任意矩形拖拽框选，并通过 `AutomationOCRSearchRegionSelection` 转换成当前选择的 display/window/content region space。
- `AutomationOCRRegionEditorView` 提供 region preview、X/Y/W/H 微调、Clear Region、多显示器提示，以及 window/content context 不可用时的明确反馈。
- `AutomationWorkflowPackagePresenter` 提供 `.sparkrec_workflow` import/export/share，支持 selected/all workflow package、duplicate workflow conflict prompt，以及 missing local macro reference prompt；导入结果仍通过 reducer `upsertWorkflow` 进入持久化。
- `AutomationExternalSignalSourceView` 和 `AutomationManualApprovalPresenter` 提供真实产品来源，并通过 `LiveAutomationRuntimeHost` provider injection 进入 Owner B。
- `AutomationResourceTimelineView` 只显示用户可理解的资源标签，不暴露 internal channel 编号。

第二版再做：

- 拖拽调度时间。
- 条件边颜色。
- 级联后推动画。
- 拖拽调度时间的直接 authoring。
- 更细的条件边视觉语义。

## 验收条件

- 100 个节点、200 条边时拖拽不卡顿到不可用。
- FlowGraph edge 由 Canvas 绘制。
- View body 不直接做 DAG 搜索或全量 layout 计算。
- UI 不直接调用 Player/Scheduler/ResourceArbiter。
- UI action 只发送 reducer action。
- manual approval / external signal 只通过 provider/view-intent 边界进入 runtime。
- task inspector 只展示 `AutomationTaskRun` 的 timing/outcome/evidence metadata，不加载截图、宏包或 Player 运行对象。
- OCR region picker 通过 product picker 写入 task condition，再用 reducer action 保存。
- OCR region editor 可预览/微调 bounds，并提示 display/window/content 空间上下文。
- workflow package import/export/share 使用 Owner B codec，不在 SwiftUI 解释 JSON 字段。
- workflow package import 会提示本地缺失的 macro 引用，但不把 macro payload 塞进 package。
