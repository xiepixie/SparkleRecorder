# Workflow CLI Product Contract

本文件设计 SparkleRecorder Workflow CLI。目标不是做一个薄薄的 import/export 工具，而是提供一套 AI 和高级用户都能逐步操纵 workflow 的稳定接口：发现宏、创建草稿、编辑每个节点和连线、校验、模拟、导入，并最终触发运行。

## Product Goals

1. 工作流能按规范稳定触发：定时、手动、依赖、timeout、retry、资源等待都能被 CLI 校验和模拟。
2. AI 能访问系统：读取宏库、理解已有 workflow、生成草稿、逐步修改每个 task/dependency、解释问题并请求用户确认。
3. 用户可控：CLI 默认操作 draft，不直接改真实库；写入和运行必须显式确认。
4. 输出稳定：所有 AI-facing 命令必须支持 `--json`，并返回统一 envelope。
5. 不暴露内部 Swift Codable enum：AI 使用 `sparkle.workflow.draft.v1`，由 CLI 编译成内部 `AutomationWorkflow`。

## Mental Model

用户想说的是：

- “有哪些宏可以用？”
- “帮我搭一个晚上 3 点跑的流程。”
- “这个等待文本节点改成等 120 秒。”
- “如果找不到按钮，就先点一下屏幕再继续等。”
- “导入前告诉我会发生什么。”
- “现在运行这个 workflow，然后告诉我卡在哪里。”

CLI 应该围绕这些动作，而不是围绕内部文件路径。

## Capability Tiers

| Tier | Commands | Writes App State | Safe For AI By Default |
| --- | --- | --- | --- |
| Read | `macros`, `workflow list/show/export`, `draft inspect` | No | Yes |
| Draft | `draft init/add/set/connect/remove/patch/validate/simulate` | No, unless `--out` overwrites draft file | Yes |
| Import | `workflow import` | Yes | Only with `--confirm` or UI approval |
| Runtime | `workflow run/status/cancel/history` | Creates runs / cancels runs | No by default; requires explicit user approval |

AI 应优先停留在 Read + Draft tier。Import 和 Runtime tier 必须让用户确认。

## Output Envelope

所有 `--json` 输出使用统一结构：

```json
{
  "ok": true,
  "schema": "sparkle.cli.result.v1",
  "command": "workflow draft validate",
  "data": {},
  "warnings": [],
  "errors": [],
  "nextActions": []
}
```

错误输出也保持 JSON：

```json
{
  "ok": false,
  "schema": "sparkle.cli.result.v1",
  "command": "workflow draft validate",
  "data": null,
  "warnings": [],
  "errors": [
    {
      "code": "ambiguousMacroRef",
      "message": "Macro name matches multiple macros.",
      "path": "$.workflow.tasks[0].macroRef",
      "candidates": ["..."]
    }
  ],
  "nextActions": [
    {
      "command": "sparkle-recorder workflow macros --search \"点击屏幕\" --json",
      "reason": "Choose a specific macro ID."
    }
  ]
}
```

## Command Groups

### 1. Macro Catalog

```bash
sparkle-recorder workflow macros --json
sparkle-recorder workflow macros --search "离开" --json
sparkle-recorder workflow macro show <macro-id> --json
```

Must return:

- `id`
- `name`
- `tags`
- `durationSeconds`
- `eventCount`
- `clickCount`
- `keyCount`
- `scrollCount`
- `resourceRequirement`
- `surfaces` summary
- optional `notes`

AI rule: never invent macro IDs. Always choose from catalog results.

### 2. Existing Workflow Read

```bash
sparkle-recorder workflow list --json
sparkle-recorder workflow show <workflow-id> --json
sparkle-recorder workflow export <workflow-id> --format draft-json --json
sparkle-recorder workflow history <workflow-id> --json
```

`export --format draft-json` converts internal workflow to AI-readable draft. It should preserve task `key` values if available; otherwise it generates stable keys from task name + ID suffix.

### 3. Draft Lifecycle

```bash
sparkle-recorder workflow draft init --name "战斗循环" --out battle.json --json
sparkle-recorder workflow draft inspect battle.json --json
sparkle-recorder workflow draft normalize battle.json --out battle.normalized.json --json
sparkle-recorder workflow draft explain battle.json --json
```

`normalize` sorts tasks/dependencies, fills defaults, and formats the draft. AI should call it before showing final output.

### 4. Fine-Grained Draft Editing

These commands let AI manipulate every detail without rewriting the whole file blindly.

```bash
sparkle-recorder workflow draft task add battle.json \
  --key tap_screen \
  --type macro \
  --macro-name "点击屏幕" \
  --resource foregroundInput \
  --out battle.json \
  --json

sparkle-recorder workflow draft task set battle.json tap_screen \
  --timeout 10 \
  --retry-max 1 \
  --name "点击屏幕让按钮出现" \
  --out battle.json \
  --json

sparkle-recorder workflow draft condition set battle.json wait_exit \
  --type ocrText \
  --text "离开" \
  --match contains \
  --region battle_result_area \
  --timeout 120 \
  --polling 0.5 \
  --out battle.json \
  --json

sparkle-recorder workflow draft dependency add battle.json \
  --from tap_screen \
  --to wait_exit \
  --trigger success \
  --delay 1 \
  --out battle.json \
  --json
```

Required editing commands:

| Command | Purpose |
| --- | --- |
| `task add` | Add macro/delay/condition/notification/manualApproval task. |
| `task set` | Rename, enable/disable, timeout, retry, resource, graph position. |
| `task remove` | Remove task and dependent edges, or require `--keep-orphans false`. |
| `dependency add` | Add edge with trigger and delay. |
| `dependency set` | Change trigger, delay, enabled state. |
| `dependency remove` | Remove edge by source/target or dependency key. |
| `schedule set` | Manual/once/repeating schedule. |
| `condition set` | OCR/visual/outcome/external/manual condition details. |
| `layout set` | Optional graph position for UI. |
| `patch` | Apply batch JSON patch for AI agents that prefer one request. |

### 5. Batch Patch For AI

AI often works better by submitting a batch of operations. Support this:

```bash
sparkle-recorder workflow draft patch battle.json patch.json --out battle.json --json
```

Patch schema:

```json
{
  "schema": "sparkle.workflow.patch.v1",
  "ops": [
    {
      "op": "addTask",
      "task": {
        "key": "wait_exit",
        "type": "condition",
        "condition": {
          "type": "ocrText",
          "text": "离开",
          "matchMode": "contains"
        },
        "timeoutSeconds": 120
      }
    },
    {
      "op": "addDependency",
      "from": "tap_screen",
      "to": "wait_exit",
      "trigger": "success",
      "delaySeconds": 1
    }
  ]
}
```

Every patch result must list changed task keys, changed dependency keys, warnings, and validation state.

### 6. Validation

```bash
sparkle-recorder workflow draft validate battle.json --json
```

Validation must check:

- schema version.
- duplicate task keys.
- missing macro refs.
- ambiguous macro refs.
- cycles.
- missing dependency endpoints.
- unsupported condition type.
- resource conflict risks.
- timeout branch missing for long waits.
- repeating schedule validity.
- join policy ambiguity.
- import compatibility with current app version.

Validation should distinguish:

- `error`: cannot import or run.
- `warning`: import allowed, user should review.
- `suggestion`: useful improvement.

### 7. Simulation

```bash
sparkle-recorder workflow draft simulate battle.json --json
sparkle-recorder workflow draft simulate battle.json --scenario timeout:wait_exit --json
sparkle-recorder workflow draft simulate battle.json --at "2026-07-06T03:00:00+08:00" --json
```

Simulation is critical. It lets AI and user see what will happen without moving the mouse.

Must return:

- planned task order.
- expected scheduled times.
- resource lane occupancy.
- dependency branch decisions.
- timeout/retry behavior.
- missing branch warnings.
- generated run skeletons without real evidence.

### 8. Import

```bash
sparkle-recorder workflow import battle.json --dry-run --json
sparkle-recorder workflow import battle.json --confirm --json
```

Rules:

- `--dry-run` compiles draft to internal workflow and returns planned changes.
- `--confirm` is required to write `automations.json`.
- Import never writes `SavedMacro` runtime fields.
- Missing macro refs block import unless user supplies an explicit resolution file.
- Ambiguous macro refs block import.

### 9. Runtime Control

Runtime CLI is useful, but more dangerous. It should come after draft/import basics.

```bash
sparkle-recorder workflow run <workflow-id> --task <task-key-or-id> --json
sparkle-recorder workflow status <workflow-id> --json
sparkle-recorder workflow cancel <run-id> --confirm --json
sparkle-recorder workflow runs <workflow-id> --json
```

Rules:

- Runtime commands must go through the same reducer/runtime path as UI.
- Running a workflow can move mouse/keyboard; require explicit user confirmation unless app preference allows trusted CLI.
- Status is read-only and safe for AI.

## AI Collaboration Loop

Recommended AI flow:

1. Read macro catalog.
2. Ask user only for missing intent, not for internal IDs.
3. Create draft.
4. Validate draft.
5. Patch draft until errors are gone.
6. Simulate happy path and one failure/timeout path.
7. Explain result in user language.
8. Ask user before import.
9. Import with `--confirm`.
10. Optionally ask user before runtime start.

AI should not:

- invent macro IDs.
- write `.sparkrec_workflow` directly.
- edit `automations.json` directly.
- run mouse/keyboard actions without user confirmation.
- hide timeout/failure branches.

## User-Facing Example

Scenario: “战斗结束后点一下屏幕，等离开出现，点击离开；如果 120 秒没出现就通知我。”

```bash
sparkle-recorder workflow macros --search "点击屏幕" --json
sparkle-recorder workflow macros --search "点击离开" --json
sparkle-recorder workflow draft init --name "战斗后离开" --out battle-exit.json --json
sparkle-recorder workflow draft task add battle-exit.json --key tap_screen --type macro --macro-name "点击屏幕" --out battle-exit.json --json
sparkle-recorder workflow draft task add battle-exit.json --key wait_exit --type condition --out battle-exit.json --json
sparkle-recorder workflow draft condition set battle-exit.json wait_exit --type ocrText --text "离开" --timeout 120 --out battle-exit.json --json
sparkle-recorder workflow draft task add battle-exit.json --key click_exit --type macro --macro-name "点击离开" --out battle-exit.json --json
sparkle-recorder workflow draft task add battle-exit.json --key notify_timeout --type notification --title "未找到离开" --out battle-exit.json --json
sparkle-recorder workflow draft dependency add battle-exit.json --from tap_screen --to wait_exit --trigger success --delay 1 --out battle-exit.json --json
sparkle-recorder workflow draft dependency add battle-exit.json --from wait_exit --to click_exit --trigger conditionMatched --out battle-exit.json --json
sparkle-recorder workflow draft dependency add battle-exit.json --from wait_exit --to notify_timeout --trigger timeout --out battle-exit.json --json
sparkle-recorder workflow draft validate battle-exit.json --json
sparkle-recorder workflow draft simulate battle-exit.json --scenario timeout:wait_exit --json
sparkle-recorder workflow import battle-exit.json --dry-run --json
```

## Phase Slicing

### Phase 1: Useful Skeleton

- `workflow macros`
- `workflow draft init/inspect/normalize`
- `workflow draft task add/set/remove`
- `workflow draft dependency add/remove`
- `workflow draft validate`
- `workflow draft simulate` with deterministic fake outcomes
- `workflow import --dry-run`

### Phase 2: Write And UI Preview

- `workflow import --confirm`
- `workflow list/show/export`
- validation warnings keyed to task/dependency keys
- UI draft preview consumes same JSON

### Phase 3: Runtime

- `workflow run`
- `workflow status`
- `workflow cancel`
- `workflow runs/history`

### Deferred

- MCP server.
- Direct natural language command inside CLI.
- Background scheduler installation/login item management.

