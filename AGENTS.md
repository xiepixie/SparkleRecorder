# Agent Instructions

## Package Manager
- Use SwiftPM from repo root: `swift build`, `swift test`.
- This repo has no checked-in Xcode project as the source of truth; `Package.swift` owns targets, source inclusion, resources, and Swift 6 mode.
- Test scratch path: `.build-test/` is ignored. Remove it after local runs when you want a quiet tree: `rm -rf .build-test`.

## Source Of Truth
- Read [docs/DOCUMENTATION_STATUS.md](docs/DOCUMENTATION_STATUS.md) before large changes.
- Automation work starts at [docs/automation-engine/README.md](docs/automation-engine/README.md).
- A/B/C owner boundaries live in [docs/automation-engine/02-parallel-workstreams.md](docs/automation-engine/02-parallel-workstreams.md).
- Testing rules live in [docs/automation-engine/09-testing-plan.md](docs/automation-engine/09-testing-plan.md).
- Do not treat archived snippets in `docs/CodebaseTargetModifications.md` or old plan snapshots as current code.

## Architecture Layers
- `SparkleRecorderCore` target: pure value types, planners, reducers, state machines, effect contracts, cache keys, failure evidence builders, and mockable clients.
- App target: SwiftUI/AppKit UI, `CGEvent`, `CGEventTap`, Vision/OCR, ScreenCapture, IOKit, repository files, and live client adapters.
- Tests target: Swift Testing only; prefer pure core tests and fake/sendable clients over live macOS APIs.
- `Player.swift` and `Recorder.swift` are composition/lifecycle shells. Move reusable behavior into core or live adapter files when it becomes testable.
- SwiftUI views render projections and dispatch accepted actions/intents; they do not call Player, scheduler, repository, arbiter, OCR evaluator, or file IO directly.

## Automation Owner Boundaries
- Owner A Core/Reducer: owns `AutomationRunState`, reducer semantics, terminal ordering, dependency cascade, projection shape, and pure reducer tests.
- Owner B Adapters/Persistence: owns resource/player/scheduler/condition/repository clients, effect runner, runtime/session, app lifecycle host, and fake/live adapter tests.
- Owner C UI/Performance: owns FlowGraph, timeline, inspector, authoring UI, provider source UI, and projection/performance tests.
- Cross-owner interface changes must update the requesting owner file, affected owner file, `02-parallel-workstreams.md`, and direct tests.

## Testing
- Use Swift Testing: `import Testing`, `@Suite`, `@Test`, `#expect`, `try #require`.
- Do not move the real mouse, post real keyboard events, call real Vision/OCR, wait on wall-clock time, or touch Application Support in unit tests.
- Use fake clients, injected clocks, local fixtures, actors, or Sendable-safe boxes for mutable test state.
- Tests should not depend on order. Each test builds its own workflow/macro/run fixture.
- Cover handoff behavior at boundaries: reducer emits effects, adapters emit `AutomationAction`, UI emits reducer actions/provider inputs.
- For playback/recording changes, test pure engines and pipelines first: `PlaybackRunEngine`, `PlaybackSynchronousRunEngine`, `PlaybackRunStateMachine`, `PlaybackLocatorCache`, `RecordingEventPipeline`, `RecordingSessionProcessor`.

## File-Scoped Commands
| Task | Command |
| --- | --- |
| Targeted test | `swift test --scratch-path .build-test --enable-swift-testing --disable-xctest --filter 'PlaybackRunEngineTests'` |
| Owner B tests | `swift test --scratch-path .build-test --enable-swift-testing --disable-xctest --filter 'AutomationOwnerBClientTests|AutomationRuntimeSessionTests|PlaybackSynchronousRunEngineTests'` |
| Reducer/UI projection tests | `swift test --scratch-path .build-test --enable-swift-testing --disable-xctest --filter 'AutomationReducerTests|AutomationViewProjectionTests'` |
| Full tests | `swift test --scratch-path .build-test --enable-swift-testing --disable-xctest` |
| Swift 6 build | `swift build -Xswiftc -swift-version -Xswiftc 6` |
| Release build | `swift build -c release` |
| Whitespace check | `git diff --check` |

## Task Workflow
- Start with `git status --short --branch`; preserve unrelated user edits.
- Read the nearest implementation files, current docs, and tests before choosing an approach.
- For large changes, create or update a focused `docs/<feature>/` folder before coding.
- Pick the layer first: pure core behavior, live app adapter, UI projection, or documentation.
- Prefer extracting a small pure boundary and adding focused tests before touching live macOS code.
- Keep platform APIs at the app edge; core should not import SwiftUI, AppKit, Vision, ScreenCapture, IOKit, or mutate files.
- Update docs when the behavior changes owner contracts, accepted interfaces, test strategy, or current status.
- Verify targeted tests first, then full tests/builds when blast radius crosses core/app/runtime boundaries.

## Large Change Collaboration
- Start with docs, then code: record current state, target state, boundaries, risks, test plan, and acceptance checks.
- Use a docs folder as the shared workbench: `README.md`, `00-current-status.md`, `NN-topic.md`, `workstreams/`, and `acceptance-checklist.md` when useful.
- Split big work by owner or layer before implementation; do not let state semantics, live side effects, and UI behavior collapse into one file.
- Freeze contracts early: types, actions, effects, requests/results, persistence fields, and projection shapes.
- Every interface change needs a written request, accepted-contract note, and direct test coverage.
- Mark completion from evidence: code exists, tests pass, docs match reality, and unchecked checklist items are gone.
- Keep planning docs factual. Label future work as future work; do not describe planned behavior as implemented.

## Commit Attribution
AI commits MUST include:
```text
Co-Authored-By: (agent model name) <noreply@example.com>
```
