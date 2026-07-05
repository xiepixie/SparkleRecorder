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
  Bottom/Right: ResourceTimelineView
  Inspector: selected task/dependency settings
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

只读 UI：

- 显示 workflow tasks。
- 显示依赖边。
- 显示每个 task 的 status。
- 显示 resource timeline。

第二版再做：

- 拖拽调度时间。
- 拉线建立依赖。
- 条件边颜色。
- 级联后推动画。

## 验收条件

- 100 个节点、200 条边时拖拽不卡顿到不可用。
- FlowGraph edge 由 Canvas 绘制。
- View body 不直接做 DAG 搜索或全量 layout 计算。
- UI 不直接调用 Player/Scheduler/ResourceArbiter。
- UI action 只发送 reducer action。
