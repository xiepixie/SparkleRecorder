# Target Experience

Updated: 2026-08-25

## 1. 目标结果

首次使用者应在 90 秒内完成“每天在指定时间运行一个已有宏”，并能在不进入 graph 的情况下确认：

- 计划已保存；
- 下一次运行的绝对日期、时间和时区；
- App 是否必须保持运行；
- 是否存在权限、资源或引用问题；
- 运行后去哪里看结果和证据。

专业用户应可随时切换到 canvas/inspector，编辑多入口、多 schedule、条件、依赖和资源策略，不损失现有表达能力。

## 2. 目标信息架构

```text
Automation
├── Workflows
│   ├── Overview：状态、下一次运行、最近结果、需要处理
│   ├── Build：source bin、graph、task list、dependencies
│   ├── Schedule：入口任务计划、时区、可靠性与 readiness
│   └── Settings：名称、导入导出、危险操作
└── Runs
    ├── Active：运行、等待、可取消
    ├── History：按 workflow execution 聚合，可筛选
    └── Run Detail：摘要 → step timeline → evidence → recovery
```

这不是要求立即新增所有顶级页面。V1 可在当前三栏布局中以中央 tab 和详情 sheet 实现，但对象边界必须按上述结构组织。

## 3. 快速创建流程

### Step 1：选择目标

- 默认选项：“定时运行一个宏”。
- 次级选项：“构建多步骤工作流”进入现有 canvas。
- 显示宏的名称、时长/事件摘要和最近可用性；允许当场录制新宏。

### Step 2：选择时间

默认提供：

- 手动运行；
- 一次；
- 每天；
- 工作日；
- 每周；
- 自定义间隔（高级）。

始终展示自然语言摘要，例如“每个工作日 09:00，本地时区”，并显示至少下一次 occurrence 的完整日期。跨夏令时或时区规则应写明采用的策略；在 core 合同冻结前不得用含糊文案掩盖。

### Step 3：运行前检查

检查项按三类呈现：

- **阻断**：缺失 macro、无效 visual asset、必需权限缺失、计划无下一次 occurrence。
- **警告**：App 需要保持运行、窗口/资源可能不可用、证据目录不可写等。
- **就绪**：引用有效、时间可解析、下一次运行已确定。

每条必须包含：短标题、具体解释、修复动作、是否阻止启用。检查结果必须来自 projection/client 合同，View 不自行访问系统权限或文件。

### Step 4：确认并启用

确认页只强调：宏/起点、时间、下一次运行、可靠性限制、证据策略。主按钮使用“保存并启用”；保存成功后显示 receipt，而不是静默返回 canvas。

成功态提供三个动作：

- 完成；
- 立即测试运行；
- 打开高级编辑。

## 4. Workflow Overview

选中 workflow 后，首屏顶部固定回答四件事：

1. **状态**：未配置、需处理、已计划、运行中、已暂停。
2. **下一次运行**：完整日期/时间；无计划时解释原因。
3. **最近结果**：成功/失败/取消及耗时。
4. **主要动作**：运行、暂停/启用、查看问题或查看当前运行。

列表行采用相同信息优先级：名称 → reliability/status → next run → latest result。导入/导出/分享移入上下文菜单，避免和“新建”争夺主路径。

## 5. Schedule 页面

### 单入口 workflow

将唯一入口 task 的 schedule 作为工作流计划呈现，但文案注明“从〈task name〉开始”。编辑仍提交 task schedule action。

### 多入口或多 schedule workflow

不合并成虚假的全局 schedule。展示“3 个计划入口”的列表，每行包含 task、规则、下一次运行、启用状态和问题。用户可选择入口编辑。

### 高级设置

timeout、retry、resource max wait、schedule end 等保持 task 级并渐进披露。timeline 负责预览和冲突解释，不再同时承担常见 schedule 的首要表单入口。

## 6. Run Center

### Execution 聚合

一次用户启动或定时触发产生一个 execution 记录视图，以 `executionID` 聚合同链 task runs。详情页结构：

```text
结果摘要
触发来源 / 开始结束 / 总耗时 / 起点
需要处理的主要问题 + 主恢复动作
步骤时间线（queued → waiting → running → outcome）
关键证据
全部诊断与原始资料（折叠）
```

若历史数据无法可靠聚合，明确标为“单步骤运行记录”，不能猜测 execution 边界。

### 运行中反馈

- 命令提交后立即显示“已接受”，并在 reducer action 到达后切换为 queued/running。
- 当前 task、触发边、等待资源/条件和 retry attempt 在 graph 与 Run Center 使用同一 projection。
- 等待状态显示等待对象、已等待时间、deadline 和可执行动作。
- cancel 是 execution 级主动作；task 级取消只在专业详情中出现。

## 7. Evidence Workspace

证据不再以文件类型作为第一层，而按问题组织：

1. **发生了什么**：失败 task、用户可读原因、发生时间。
2. **系统观察到什么**：关键截图/裁剪、OCR 文本、匹配分数、branch decision。
3. **为什么这样判断**：threshold、region、attempt、资源/权限上下文。
4. **接下来做什么**：修复引用/权限/条件、打开或 reveal artifact、重新运行。

默认只展示一个关键证据卡。其余证据按 task 和时间排序。每个 artifact 必须显示：所属 run、采集时间、类型、可用性、是否为 legacy fallback；预览不可用不应隐藏 report。

## 8. 恢复动作语义

| 动作 | V1 语义 | 保护规则 |
| --- | --- | --- |
| 重新运行 | 从同一起点创建新的 execution | 不覆盖旧 run/evidence |
| 打开任务设置 | 选择失败 task 并定位相关 section | 不由证据 View 直接改 model |
| 修复权限 | 打开解释/系统设置入口 | 检查后重新评估 readiness |
| Reveal/Open evidence | 通过 app-edge presenter 处理文件 | 缺失时显示原因，不崩溃 |
| 从失败点重试 | V1 暂不提供，除非 reducer 明确定义依赖与上游语义 | 禁止只在 UI 拼接 manualStart |

## 9. 文案和视觉规则

- 面向用户使用“计划、运行、步骤、结果、证据”；task/run ID、manifest、lease 等放到诊断区。
- 状态色只辅助，不作为唯一信息；所有状态有图标和文本。
- 普通控件保持 macOS 原生克制风格；高饱和背景只服务运行、失败、drop target 或危险确认。
- 日期默认显示绝对值；“明天”可作为辅助，不能单独出现。
- 空状态必须提供下一步操作，不能只说“暂无数据”。
- 所有关键动作支持 VoiceOver label、键盘焦点和 Reduce Motion。

## 10. 不在 V1 假装解决的问题

- OS wakeup、login item、daemon/background session；
- priority/preemption/cross-process resource arbitration；
- 任意“从失败点继续”的 reducer 语义；
- 跨设备运行、云同步或远程通知；
- 自动删除/压缩证据的 retention 产品策略；
- cron 表达式编辑器。
