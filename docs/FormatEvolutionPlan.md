# SparkleRecorder Format Evolution Plan

本文定义 SparkleRecorder 宏、脚本和未来视觉自动化资源的格式命名与演进方向。

## 1. 命名建议

当前不建议立刻把现有 `.tinyrec` 全量改名，因为它已经是导入、导出、Finder 打开、CLI 和测试都依赖的兼容格式。更稳的路线是：

| 格式 | 状态 | 用途 |
| --- | --- | --- |
| `.tinyrec` | 保留兼容 | 当前 v3 单文件 JSON 宏格式 |
| `.trm` / `.txt` | 保留兼容 | 当前可手写文本宏格式 |
| `.command` | 保留 | macOS 自运行脚本导出 |
| `.sparkrec` | 新增推荐 | Spark Record v4 压缩包格式，承载一个完整录制 |
| `.sparkflow` | 未来可选 | 多宏、状态机、定时任务和复杂编排 |

推荐品牌命名：

- 用户看到的正式名称：SparkleRecorder Recording
- 文件短名：Spark Record
- 扩展名：`.sparkrec`
- 格式标识：`com.sparklerecorder.recording`

## 2. 为什么需要包格式

单个 JSON 文件适合普通录制，但未来如果支持实图、OCR、模板匹配、定时任务和状态编排，会遇到这些问题：

- 图片模板和失败截图不适合 base64 塞进 JSON。
- OCR 识别结果、截图证据、窗口快照和调试日志会快速膨胀。
- 状态机、调度计划、动作图和原始事件混在一个 JSON 里会难维护。
- 用户分享宏时需要一个可复制、可版本化、可校验的完整资产包。

因此新格式建议是“目录结构 + zip 压缩包”。开发时可以把它当文件夹处理，导出时封装为一个 `.sparkrec` 文件。

## 3. `.sparkrec` 建议结构

```text
My Workflow.sparkrec
├── manifest.json
├── macro.json
├── actions.json
├── raw-events.json
├── surfaces.json
├── assets/
│   ├── templates/
│   │   └── button-save.png
│   ├── screenshots/
│   │   └── recorded-window.png
│   └── ocr/
│       └── recorded-window.ocr.json
├── schedules/
│   └── schedule.json
├── state/
│   └── state-machine.json
└── runs/
    └── latest/
        ├── result.json
        └── failure.png
```

## 4. 文件职责

| 文件 | 职责 |
| --- | --- |
| `manifest.json` | 格式标识、schema 版本、创建者、兼容范围、资源索引 |
| `macro.json` | 当前 `SavedMacro` 的元数据、循环、速度、标签、热键、链式播放 |
| `actions.json` | 语义动作层，供编辑器、状态机和编排器使用 |
| `raw-events.json` | 当前 `RecordedEvent` 数组，保留精确回放能力 |
| `surfaces.json` | 录制窗口、显示器、内容区和坐标空间信息 |
| `assets/templates/` | 图像模板、按钮截图、局部匹配素材 |
| `assets/screenshots/` | 录制参考截图或失败证据截图 |
| `assets/ocr/` | OCR 检测结果、文字框和置信度缓存 |
| `schedules/schedule.json` | 定时任务、触发条件、节流策略 |
| `state/state-machine.json` | 状态编排、条件分支、重试和恢复策略 |
| `runs/` | 运行结果、失败证据、调试日志 |

## 5. `manifest.json` 草案

```json
{
  "format": "com.sparklerecorder.recording",
  "schemaVersion": 4,
  "kind": "recording",
  "createdBy": "SparkleRecorder",
  "minimumAppVersion": "1.9.0",
  "primaryMacro": "macro.json",
  "actions": "actions.json",
  "rawEvents": "raw-events.json",
  "assets": {
    "templates": "assets/templates",
    "screenshots": "assets/screenshots",
    "ocr": "assets/ocr"
  }
}
```

## 6. 迁移策略

阶段 1：保持当前 `.tinyrec` 不变。

- 继续支持 `.tinyrec` 导入导出。
- README 中把 `.tinyrec` 标记为 legacy-compatible native JSON。
- 新代码只新增格式抽象，不破坏现有用户文件。

阶段 2：新增 `.sparkrec` 导出。

- 写一个 `RecordingPackageWriter`。
- 从 `SavedMacro` 生成 `macro.json`、`raw-events.json`、`surfaces.json`。
- 暂时允许 `assets/` 为空。

阶段 3：新增 `.sparkrec` 导入。

- 写 `RecordingPackageReader`。
- 优先读取 `manifest.json`。
- 缺失语义动作时可从 `raw-events.json` 重新 group。

阶段 4：视觉和状态编排。

- OCR picker 保存截图、OCR cache 和 text anchors。
- 模板匹配动作保存模板资源和匹配参数。
- 定时任务和状态机写入 `schedules/` 与 `state/`。

## 7. 设计原则

- 原始事件永远保留，保证最低限度可回放。
- 语义动作可以重建，但用户编辑后的动作名、分组和参数要持久化。
- 视觉资源用文件保存，不塞进 JSON。
- 包格式必须可解压、可 diff、可调试。
- 所有 schema 都带版本号，导入器必须做向后兼容。
