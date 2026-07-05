# AI Interface: CLI First, MCP Deferred

SparkleRecorder 需要给 AI 一个稳定接口，让 AI 能根据宏库生成可验证、可导入的工作流。本阶段只开发一个接口：CLI-first。MCP 暂缓，等 CLI 合同稳定后再评估是否包装同一套能力。

CI 不是 AI 接口，也不属于 MCP/CLI 选型。后续可以用 CI 做回归验证，但它不是本阶段的产品接口目标。

## Recommendation

| Option | Use For | Recommendation |
| --- | --- | --- |
| CLI | 本地 AI Agent、脚本初始化、验证、模拟、导入、导出 | 本阶段唯一实现。CLI 稳定、易测、能复用现有 SwiftPM/命令行基础。 |
| MCP | ChatGPT/Codex/其他 Agent 的结构化工具访问 | 暂缓。不和 CLI 并行开发；未来只包装同一套 validator/resolver/importer。 |
| CI | 回归验证 | 不作为 AI 接口规划。未来可验证 samples 和 roundtrip，但不是本阶段目标。 |

不要让 AI 直接生成 `.sparkrec_workflow` 内部包。`.sparkrec_workflow` 继续服务产品导入导出；AI 应生成 `sparkle.workflow.draft.v1`，再由 resolver 编译到内部模型。

## External Draft Schema

草稿 schema 使用稳定、人类可读、AI 友好的 key，不暴露 Swift Codable enum 细节。

```json
{
  "schema": "sparkle.workflow.draft.v1",
  "workflow": {
    "name": "战斗循环",
    "tasks": [
      {
        "key": "tap_to_reveal_exit",
        "type": "macro",
        "macroRef": { "name": "点击屏幕" },
        "resource": "foregroundInput",
        "timeoutSeconds": 10,
        "retry": { "maxAttempts": 1 }
      },
      {
        "key": "wait_exit_text",
        "type": "condition",
        "condition": {
          "type": "ocrText",
          "text": "离开",
          "matchMode": "contains",
          "regionRef": "battle_result_area",
          "requireVisible": true
        },
        "timeoutSeconds": 120,
        "pollingSeconds": 0.5
      },
      {
        "key": "click_exit",
        "type": "macro",
        "macroRef": { "name": "点击离开" },
        "resource": "foregroundInput"
      },
      {
        "key": "notify_timeout",
        "type": "notification",
        "severity": "warning",
        "title": "未找到离开按钮"
      }
    ],
    "dependencies": [
      { "from": "tap_to_reveal_exit", "to": "wait_exit_text", "trigger": "success", "delaySeconds": 1 },
      { "from": "wait_exit_text", "to": "click_exit", "trigger": "conditionMatched" },
      { "from": "wait_exit_text", "to": "notify_timeout", "trigger": "timeout" }
    ]
  }
}
```

## Phase 1 Required CLI Commands

完整 CLI 产品合同见 [05-cli-product-contract.md](05-cli-product-contract.md)。本文件只记录接口选型和最小命令方向。

推荐命令形态：

```bash
sparkle-recorder workflow macros --format json
sparkle-recorder workflow draft validate draft.json --json
sparkle-recorder workflow draft simulate draft.json --json
sparkle-recorder workflow import draft.json --dry-run --json
sparkle-recorder workflow import draft.json --confirm --json
sparkle-recorder workflow export --workflow-id <id> --format draft-json
```

CLI 输出必须稳定，供本地 AI Agent、脚本和后续 UI draft preview 解析。

## Deferred MCP Tools

MCP 不在本阶段开发。未来如果需要 MCP，它不能另写一套语义，只能包装 CLI 或共享同一套 validator/resolver/importer。

| Tool | Purpose |
| --- | --- |
| `list_macros` | 返回宏名称、ID、标签、总时长、资源需求、可用描述。 |
| `validate_workflow_draft` | 检查 schema、DAG、宏引用、条件类型、资源规则。 |
| `simulate_workflow` | 用假时钟和假 outcomes 生成预计 run/timeline/warnings。 |
| `import_workflow_draft` | 编译并持久化 workflow，返回 workflowID 和 warnings。 |
| `export_workflow_draft` | 把已有 workflow 转成 AI 可读 draft，用于解释/修改。 |

## Prompt Contract For AI

给 AI 的系统提示应包含：

- 只能使用 `sparkle-recorder workflow macros --format json` 返回的宏，不要编造宏 ID。
- 输出必须是 `sparkle.workflow.draft.v1` JSON。
- 每个 task 必须有稳定 `key`。
- 每条 dependency 必须声明 `trigger`。
- 需要前台鼠标键盘的宏默认互斥。
- 条件优先使用用户可理解类型：等待文本、等待图标出现、等待区域变化、等待图标消失。
- timeout 和 failure 必须显式分支，不要隐藏成普通失败。
- 不输出内部 Swift enum 结构，不输出 `.sparkrec_workflow`。

## Future Verification

未来可以用 CI 或本地测试验证：

- draft schema samples 可以 validate。
- draft -> internal workflow -> package -> decode roundtrip。
- simulation 对固定 fake clock 稳定。
- imported workflow 不写入 `SavedMacro` runtime fields。
- sample AI drafts 覆盖 success、timeout、resource waiting、missing macro warning。

这些验证不负责回答用户问题，也不负责选择宏；它们只防止合同漂移。
