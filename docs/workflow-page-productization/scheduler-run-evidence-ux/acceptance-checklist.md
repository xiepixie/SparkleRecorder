# Acceptance Checklist

Updated: 2026-08-25

规则：只有同时具备代码、direct tests、文档更新和要求的产品证据时才能勾选。当前文件是未来实施门槛，不代表已完成。

## Contract

- [ ] Activation/readiness projection 由 Owner A 接受并有 pure tests。
- [ ] Execution 聚合、排序和 terminal outcome 规则由 Owner A 接受并有 pure tests。
- [ ] Scheduler capability、command receipt、evidence artifact client 由 Owner B 接受并有 fake-client tests。
- [ ] UI 只读取 projection、提交 intent/action，不直接调用 runtime、repository、Player、scheduler 或 file IO。
- [ ] 跨 owner 变更同步更新 owner 文件与 `02-parallel-workstreams.md`。

## Quick setup

- [ ] 用户可选择“定时运行一个宏”或“构建多步骤工作流”。
- [ ] 一次、每天、工作日、每周 preset 可映射为确定的 core schedule。
- [ ] 摘要显示规则、绝对 next occurrence 和时区。
- [ ] 多入口 workflow 不被错误显示为单一全局 schedule。
- [ ] 保存前显示 blocking/warning/ready checks，且每项有解释和恢复动作。
- [ ] 在后台唤醒落地前，所有计划确认态显式说明 App 需要保持运行。
- [ ] 保存成功提供 receipt，并可立即测试运行或打开高级编辑。

## Overview and run center

- [ ] Workflow 列表优先显示 reliability/status、next run 和 latest result。
- [ ] Import/export/share 不与主要创建动作争夺视觉优先级。
- [ ] Manual start 在不选择 task 的普通路径下有确定起点或选择提示。
- [ ] Start/cancel 显示 accepted → queued/running → terminal 的反馈。
- [ ] Runs 按 execution 聚合；不完整旧数据明确标识。
- [ ] Waiting 状态显示对象、原因、时长、deadline 和允许动作。
- [ ] Graph、timeline、Run Center 对同一状态使用同一 projection。

## Evidence and recovery

- [ ] Run detail 先展示用户可读结果与 primary issue，再展示技术诊断。
- [ ] Step timeline 能关联 task outcome、branch/condition evidence 和 retry attempt。
- [ ] 默认关键证据能在两次交互内到达。
- [ ] Evidence 标识 exact、legacy fallback、missing、unreadable。
- [ ] Screenshot 不可预览时 report 和其他诊断仍然可见。
- [ ] Open/Reveal 只通过 app-edge presenter/client。
- [ ] Rerun 创建新 execution，旧 run/evidence 不被覆盖。
- [ ] “从失败点继续”在 reducer 语义冻结前不出现。

## Accessibility and language

- [ ] 关键状态不仅依赖颜色，同时有文本和图标。
- [ ] Quick setup、Run Center 和 evidence disclosure 可全键盘操作。
- [ ] VoiceOver 能读出状态、下一次运行、问题与动作结果。
- [ ] Reduce Motion 下运行反馈不依赖动画。
- [ ] 日期有绝对值；相对日期只作辅助。
- [ ] 用户主路径不暴露 manifest、lease、raw ID 等引擎术语。
- [ ] 新增字符串使用 domain-specific `.xcstrings`。

## Automated evidence

- [ ] Preset/schedule、DST、next occurrence tests 通过。
- [ ] Readiness severity/primary issue tests 通过。
- [ ] Execution aggregate/mixed outcome/retry tests 通过。
- [ ] Evidence key-item/binding tests 通过。
- [ ] Fake capability/permission/artifact/receipt client tests 通过。
- [ ] UI intent/projection tests 覆盖 ready、blocked、running、waiting、failed 和 missing evidence。
- [ ] `swift test --scratch-path .build-test --enable-swift-testing --disable-xctest` 通过。
- [ ] `swift build -Xswiftc -swift-version -Xswiftc 6` 通过。
- [ ] `git diff --check` 通过。

## Product evidence

- [ ] Quick-create and schedule 录屏。
- [ ] Blocked readiness 和 App-online warning 截图。
- [ ] Scheduled idle 和 next occurrence 截图。
- [ ] Running/waiting execution 录屏。
- [ ] Success、failed、legacy fallback、preview unavailable 详情截图。
- [ ] 修复并 rerun 的连续录屏，证明旧 evidence 仍可访问。
