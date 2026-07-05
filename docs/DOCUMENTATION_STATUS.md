# SparkleRecorder Documentation Status

Updated: 2026-07-05

This index records which docs are active plans, which are implementation references, and which are archival. "Done" means the capability is present in the current worktree or is already covered by tests; it does not mean the whole product migration is finished.

## Current Completion Snapshot

| Area | Status | Source of Truth |
| --- | --- | --- |
| Swift 6 baseline | Done in current worktree | `Package.swift` and `DomainSendableTests` |
| Swift Testing baseline | Done | `Tests/SparkleRecorderTests` uses `Testing`, `@Test`, `#expect` |
| Recording boundary split | Mostly done | `RecordingEngineClient`, `LiveRecordingEngineClient`, `RawInputEvent`, `RecordingEventPipeline`, `RecordingSessionProcessor` |
| Event tap start failure feedback | Done in current worktree | `EventTapThread.startAndWait`, `Recorder.startRecording() -> Bool` |
| Recording high-frequency buffering | Done in current worktree | `RecordingEventBuffer` and bounded `AsyncStream` policy |
| Playback ordinary step executor | Mostly done | `PlaybackStepExecutor` and tests |
| Playback failure evidence value model | Mostly done | `PlaybackFailureEvidence`, `PlaybackFailureEvidenceBuilder`, `PlaybackEvidenceClient` |
| SwiftUI selection recalculation control | Done in current worktree | `ActionGroupSelectionSnapshot`, `ActionGroupProjectionTests` |
| AutomationEngine core contract | Not started in code | `docs/automation-engine/01-core-contract-first.md` |
| Workflow reducer and state machine | Not started in code | `docs/automation-engine/03-reducer-state-machine.md` |
| ResourceArbiter panic release | Not started in code | `docs/automation-engine/04-resource-arbiter.md` |
| SchedulerClient and timed starts | Not started in code | `docs/automation-engine/06-scheduler-client.md` |
| FlowGraph and Resource Timeline UI | Not started in code | `docs/automation-engine/08-ui-flowgraph-timeline.md` |

## Document Roles

| Document | Role | Status |
| --- | --- | --- |
| `ArchitectureAndTestingModernizationPlan2026.md` | Master architecture and testing direction | Active plan. Use with this status index because early "current state" notes are an audit snapshot. |
| `SparkleRecorderArchitecture.md` | Product architecture snapshot | Active reference. Needs refresh after AutomationEngine lands. |
| `RecordingEngineRefactoringPlan.md` | Recording migration plan | Partially implemented. Keep remaining actor/performance work here. |
| `WindowBoundAutomationPlan.md` | Window/OCR/semantic automation architecture | Partially implemented reference. Automation condition routing now belongs to `automation-engine/`. |
| `VisionArchitecturePlan.md` | OCR and visual targeting rules | Active reference. State tree work has moved to AutomationEngine planning. |
| `FormatEvolutionPlan.md` | `.tinyrec`, `.sparkrec`, `.sparkflow` evolution | Deferred reference. First workflow persistence should use `automations.json`. |
| `CodebaseTargetModifications.md` | File-level target-change notes | Archive. Do not treat snippets as exact current source. |
| `MacroEditorUserGuide.zh-Hans.md` | User-facing editor guide | Active user doc. Does not cover future FlowGraph UI yet. |
| `RepositorySubmissionPlan.md` | Repository publication checklist | Archive/reference. Re-check before push. |
| `automation-engine/` | Automation scheduling, dependency, reducer, resource, UI and testing plan | Active workstream. Phase 0 core contract is the next required code step. |

## Next Required Sequence

1. Freeze the Automation Core contract.
2. Implement reducer state transitions with Swift Testing.
3. Add `ResourceArbiter` with idempotent release and panic release.
4. Wrap Player and Scheduler behind mockable clients.
5. Add workflow persistence and run history without polluting `SavedMacro`.
6. Build FlowGraph/Resource Timeline from reducer projections only.
