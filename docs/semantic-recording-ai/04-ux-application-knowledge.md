# UX And Application Knowledge

更新时间：2026-07-06
状态：产品规划

## User Story

用户录制宏时并不只是保存“我点了哪里”。用户真正想保存的是：

- 这个应用里某个功能怎么完成。
- 哪些步骤必须按顺序做。
- 哪些地方要等文字、图案、颜色或页面状态出现。
- 哪些输入是变量。
- 哪些操作是误触或人为等待。
- 下一次遇到同类任务时，能不能不用重新录制。

因此录制完成后的 UX 应该是 Review And Teach，而不是只给一个事件列表。

## Recording Review UX

录制停止后进入 Review：

- 左侧是视频/关键帧时间线。
- 中间是当前帧和可选 OCR/visual/AX overlays。
- 下方是输入事件和自动分组步骤。
- 右侧是 AI suggestions 和 Inspector。

用户可以：

- 给宏写目的说明。
- 删除误触或无效等待。
- 将长等待改成 “等待文字/图案/像素/区域变化”。
- 从帧中框选 visual asset。
- 把点击改成 “点击文字附近 / 点击图像中心 / 点击 AX 按钮”。
- 标记变量输入，例如订单号、日期、搜索关键词。
- 接受或拒绝 AI 提议。

## Visual Wait UX

等待和验证类动作应该让用户感觉“系统在观察这里”，而不是“系统要点击这里”。

第一版需要把这些动作作为用户语言明确区分：

| User Intent | UI Meaning | Visual Treatment |
| --- | --- | --- |
| 等待文字出现 | 观察一块区域直到 OCR 命中 | region box + label |
| 验证文本存在 | 检查一块区域是否符合预期 | region box + label |
| 等待图标出现 | 在搜索范围内匹配 template | search region + template thumbnail |
| 等待图标消失 | 观察 template 不再命中 | search region + disappearance state |
| 等待区域变化 | 比较 recorded baseline 和 runtime sample | baseline region + change threshold |
| 等待像素状态 | 等待某点颜色进入目标范围 | pixel marker + sampled color |
| 点击位置/文字/图像 | 执行实际输入动作 | click circle/pulse + target label |

只有点击类动作使用圆点、光圈或脉冲。等待文本、验证文本、区域变化和 baseline comparison 默认只显示框、编号和状态，避免暗示系统会点击。

## Fixing Human Recording Imperfections

人工录制天然有瑕疵，系统应帮助优化：

| Imperfection | Suggested Optimization |
| --- | --- |
| 等待过长 | 建议替换为 OCR/image/region wait，保留 max timeout |
| 点击偏移 | 建议绑定到最近文字、图像模板、AX element 或 recorded window-local point |
| 误触 | 标记为 removable segment，要求用户确认 |
| 重复输入 | 建议合并为 text input burst |
| 页面加载不稳定 | 建议增加 wait/assert condition |
| 滚动过多 | 建议使用 text locator 或 scroll-until-text |
| 多次打开同一 app/window | 建议绑定 surface 和 app context |

每个优化都必须可解释：显示 before frame、after frame、相关事件和推荐理由。

## Application Knowledge Library

更长远的愿景是让 SparkleRecorder 逐渐理解某个应用的功能地图。不是通过一次大模型扫描整个 app，而是通过用户自己的录制积累：

```text
Application Knowledge
  app bundle id
  known windows / surfaces
  known macros
  known visual anchors
  known input fields
  known buttons / menu paths
  known state transitions
  known failure cases
```

同一个应用、同一批窗口、同一类业务流程的宏应能组织在一个 folder / app workspace 中：

- app folder: `Safari Checkout Automation`
- surface group: checkout page, confirmation page, report page
- macro group: login, search, export, submit, confirm
- visual asset group: buttons, status badges, result regions
- workflow group: end-to-end tasks composed from macros

## AI Composition Scenario

用户未来可以说：

> 帮我在这个应用里搜索今天的订单，导出 CSV，然后发通知。

AI 不应该立刻要求重新录制。它应该：

1. 查询 app knowledge。
2. 找已有宏和 visual anchors。
3. 判断缺口：已有搜索宏、导出宏、通知 task，缺日期输入变量。
4. 生成 workflow draft 或 macro draft proposal。
5. 在 UI 中说明 “复用了哪些录制”、“哪些步骤需要用户确认”。
6. 用户确认后 import workflow。

如果证据不足，AI 应明确说需要补录哪个最小片段，例如 “请录制一次如何打开导出菜单”。

## UX Principles

- 用户看到的是“动作意图”，不是 raw event noise。
- 视频是信任来源，AI suggestion 必须能回到视频帧。
- AI 负责提出优化，用户负责接受。
- 常用宏按应用和任务组织，而不是只按文件名堆叠。
- 对同一应用，历史录制会变成可复用知识，而不是孤立片段。
- CLI 和 UI 使用同一套语义结果，避免 AI 和用户看到两套真相。

## Product Milestones

### Milestone 1: Video Review Macro

- 录制宏时保存视频/关键帧。
- 宏详情页可 scrub frame。
- 每个 click/key event 能跳到附近 frame。

### Milestone 2: Visual Asset From Recording

- 用户从 recorded frame 框选 region。
- 生成 OCR region、image template、baseline、pixel sample。
- 这些 asset 可进入 Workflow visual condition。

### Milestone 3: AI Recording Explanation

- CLI 生成 macro explanation。
- UI 显示 AI 对步骤的解释和不确定性。
- 用户可编辑目的说明和步骤名称。

### Milestone 4: AI Cleanup Suggestions

- CLI 建议等待压缩、locator 替换、误触删除。
- 所有建议引用 frame/event evidence。

### Milestone 5: Draft From Recording

- 从一个或多个 recording 生成 `sparkle.workflow.draft.v1`。
- 走现有 validate/simulate/dry-run/import。

### Milestone 6: App Knowledge Workspace

- 同应用宏自动分组。
- AI 可查询已有宏/anchors/conditions。
- 自然语言 goal 可组合已有能力生成新 workflow draft。
