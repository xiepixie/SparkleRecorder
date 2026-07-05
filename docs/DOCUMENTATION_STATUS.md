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
| Playback run lifecycle state machine | First pass done | `PlaybackRunStateMachine` and tests |
| Playback live run engine | First pass done | `PlaybackRunEngine` and `PlaybackRunEngineTests` |
| Playback live locator/OCR step client | First pass done | `LivePlaybackRunStepClient`, `PlaybackLocatorCache`, `PlaybackLocatorCacheTests` |
| Playback synchronous run engine | First pass done | `PlaybackSynchronousRunEngine`, `LivePlaybackSynchronousRunStepClient`, `PlaybackSynchronousRunEngineTests` |
| SwiftUI selection recalculation control | Done in current worktree | `ActionGroupSelectionSnapshot`, `ActionGroupProjectionTests` |
| AutomationEngine core contract | Done in current worktree | `AutomationContract.swift`, `AutomationContractTests` |
| Workflow reducer and state machine | Done in current worktree | `AutomationReducer.swift`, `AutomationReducerTests`, `AutomationViewProjection` |
| ResourceArbiter and panic release | Done in current worktree | `AutomationResourceArbiter.swift`, `AutomationOwnerBClientTests` |
| SchedulerClient and timed starts | Done in current worktree | `AutomationSchedulerClient.swift`, `AutomationRuntimeSession.swift`, `AutomationOwnerBClientTests` |
| FlowGraph and Resource Timeline UI | First pass done | `AutomationMainView`, FlowGraph projection views, Resource Timeline views, `AutomationViewProjectionTests` |

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
| `automation-engine/` | Automation scheduling, dependency, reducer, resource, UI and testing plan | Active workstream. Phase 0 core contract is done; three-owner planning lives in `automation-engine/workstreams/`. |
| `workflow-page-productization/` | Next-stage Workflow page, CLI-first AI interface, and two-owner productization plan | Active plan. Use this for the next phase where Engine/Runtime contracts feed a redesigned usable Workflow page. |

## Next Required Sequence

1. Freeze the Workflow page product contract in `workflow-page-productization/`.
2. Implement backend ready-for-ui notices for scheduler occurrences, resource waiting, timeout/retry, join policy, visual conditions, and CLI-first AI draft validation.
3. Rebuild the Workflow UI from fixtures before live wiring.
4. Evaluate product-level scheduler launch integration such as `NSBackgroundActivityScheduler` or login item.
5. Polish release-facing AutomationEngine documentation after product flows stabilize.
6. Refresh product-facing docs after AutomationEngine UI stabilizes.
