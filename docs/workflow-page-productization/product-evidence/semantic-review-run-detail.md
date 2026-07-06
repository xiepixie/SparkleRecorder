# Semantic Review Run Detail

- Capture date: 2026-07-06
- Evidence type: fixture product evidence
- Scenario command: `swift run SparkleRecorder workflow product-evidence snapshot semantic-review-run-detail --output docs/workflow-page-productization/product-evidence/semantic-review-run-detail.png`
- Source fixture: `AutomationRunState.ownerCFixture` with `Upload report` macro carrying `SavedMacro.semanticRecording`
- UI surface: `AutomationMainContentView` -> `AutomationTaskRunDetailView`
- Screenshot file: `semantic-review-run-detail.png`
- Checklist item: S3 linked Run Detail -> Macro Review opener metadata and bundle reveal affordance
- Worktree note: generated from the fixture snapshot command in the current dirty multi-owner worktree; the linked semantic recording metadata is deterministic fixture data.
- Known gaps: this screenshot is fixture product evidence, not a live installed-app clip. Real Open/Reveal interaction recording, live bundle existence, suggestion accept/reject recording, and per-run/session semantic recording metadata remain open.

## Acceptance Notes

- The selected run resolves the `Upload report` saved macro and its `SavedMacro.semanticRecording` reference.
- Run Detail shows the Macro Review entry before opening the sheet, including Open, Reveal and manual bundle controls.
- The linked Macro Review details show recording id, event count, captured date and manifest ref.
- Reveal is routed through `SemanticRecordingReviewPresenter.revealBundle(from:)`, so SwiftUI does not construct App Support paths directly.
- This artifact proves the fixture Run Detail linked metadata state; it does not claim live semantic recording capture or installed-app product completion.
