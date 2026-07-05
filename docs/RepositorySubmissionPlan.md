# SparkleRecorder Repository Submission Plan

本文件记录当前工作区提交到 `https://github.com/xiepixie/SparkleRecorder.git` 前的整理结论。

## 1. 当前远程状态

- `origin` 已切换为 `https://github.com/xiepixie/SparkleRecorder.git`。
- 远端 `main` 当前只有一个 `LICENSE` 文件，并且是 Apache-2.0。
- 本地 `LICENSE` 已同步为 Apache-2.0。
- 本地 `main` 和远端 `main` 没有共同历史。正式推送前建议把 SparkleRecorder 作为新的项目导入，并用 `--force-with-lease` 更新远端 `main`，因为远端目前只是许可证占位提交。

## 2. 应提交的项目内容

### 根目录

- `.gitignore`
- `AppIcon.icns`
- `AppIcon.iconset/`
- `Info.plist`
- `LICENSE`
- `Package.swift`
- `README.md`
- `build.sh`
- `notarize.sh`
- `setup_signing_cert.sh`

### 源码

- `Sources/SparkleRecorder/`
  - App shell: `AppDelegate.swift`, `main.swift`, `MainWindowController.swift`
  - Recording/playback: `Recorder.swift`, `EventTapThread.swift`, `Player.swift`, `MouseKeyboardSynthesizer.swift`
  - Data model: `RecordedEvent.swift`, `SavedMacro.swift`, `MacroLibrary.swift`
  - Import/export: `MacroImport.swift`, `TextMacroFormat.swift`
  - Window/OCR targeting: `PointResolver.swift`, `CoordinateMapper.swift`, `WindowTracker.swift`, `ScreenCaptureService.swift`, `VisionDetector.swift`, `LocatorEngine.swift`
  - Editor UI: `Components/Editor/`
  - Library UI: `Components/Library/`
  - Localization: `en.lproj/`, `zh-Hans.lproj/`

### Xcode/SwiftPM

- `SparkleRecorder.xcodeproj/`
- `Tests/SparkleRecorderTests/`

### 文档

- `docs/SparkleRecorderArchitecture.md`
- `docs/MacroEditorUserGuide.zh-Hans.md`
- `docs/VisionArchitecturePlan.md`
- `docs/RecordingEngineRefactoringPlan.md`
- `docs/WindowBoundAutomationPlan.md`
- `docs/CodebaseTargetModifications.md`
- `docs/RepositorySubmissionPlan.md`

### 工具脚本

- `tools/make_icon.swift`
- `tools/inspect_ax.swift`
- `tools/list_windows.swift`

## 3. 应删除或不再提交的旧项目内容

这些是品牌迁移后的旧路径，应该作为删除提交：

- `Sources/TinyRecorder/`
- `Tests/TinyRecorderTests/`
- `TinyRecorder.xcodeproj/`

实际文件树里这些目录已经不存在；Git 状态里出现 `D` 是正常的，表示下一次提交会删除旧路径。

## 4. 应忽略的本地产物

这些不应提交：

- `.build/`
- `.swiftpm/`
- `.DS_Store`
- `*.log`
- `DerivedData/`
- `*.xcuserstate`
- `SparkleRecorder*.app/`

当前 `.gitignore` 已覆盖这些类型。已清理的本地垃圾：

- `.DS_Store`
- `Sources/.DS_Store`
- `Tests/.DS_Store`
- `build_verbose.log`
- `test.log`

## 5. 建议的最终提交方式

因为远端是独立历史，且你还在继续修改，当前不建议立刻提交或推送。等功能修改完成后，建议执行：

```bash
git status --short
swift test
swift build -c release
git add -A
git status --short
git commit -m "Initial SparkleRecorder project import"
```

远端目前只是 Apache-2.0 LICENSE 占位提交。确认本地内容是最终导入版本后推送：

```bash
git push --force-with-lease origin main
```

推送前再次确认 `git status --short` 中没有本地垃圾文件，且 `.build/` 仍被忽略。
