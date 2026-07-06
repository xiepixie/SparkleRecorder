# Semantic Review Run Target

- Capture date: 2026-07-07
- Evidence type: fixture product evidence
- Scenario command: `swift run SparkleRecorder workflow product-evidence snapshot semantic-review-run-target --output docs/workflow-page-productization/product-evidence/semantic-review-run-target.png`
- Source fixture: `SemanticRecordingFixture.checkoutBundle()` plus a deterministic failed `AutomationTaskRun` with `failedEventIndex: 4`
- UI surface: `SemanticRecordingReviewFixtureView`
- Screenshot file: `semantic-review-run-target.png`
- Checklist item: S3 Run Detail -> Macro Review target explanation after the Review sheet opens
- Worktree note: generated from deterministic fixture data in the current dirty multi-owner worktree.
- Known gaps: this screenshot is fixture product evidence, not a live installed-app clip. Per-run/session semantic bundle metadata and installed-app Review opening remain open.

## Acceptance Notes

- Macro Review opens on the frame/event selected by `SemanticRecordingReviewRunTarget.make(run:bundle:)`.
- The inspector shows a `Run Target` block before Teach/Draft actions, explaining that Review started at the failed event reported by playback failure evidence.
- The same block renders the `SemanticRecordingReviewRunTargetEvidence` rows: `semanticReview.runTarget`, `provenanceOnly`, no workflow mutation, selected event/frame, requested/matched event indexes, target and evidence.
- Target rows expose `Target: Event #5` and `Evidence: Failure report`, so the selected frame is no longer unexplained after Run Detail opens Review.
- The existing Teach System action rows remain visible below the target context and preserve `review.draftCandidate` / Draft Preview mutation semantics.
- This artifact proves the Review surface can explain run-outcome targeting; it does not claim live per-run semantic recording binding.
