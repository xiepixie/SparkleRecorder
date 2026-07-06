# Semantic Review Timeline

- Capture date: 2026-07-06
- Evidence type: fixture product evidence
- Scenario command: `swift run SparkleRecorder workflow product-evidence snapshot semantic-review-timeline --output docs/workflow-page-productization/product-evidence/semantic-review-timeline.png`
- Source fixture: `SemanticRecordingFixture.checkoutBundle()`
- Projection: `SemanticRecordingReviewProjection`
- UI surface: `SemanticRecordingReviewFixtureView`
- Screenshot file: `semantic-review-timeline.png`
- Checklist item: S3 fixture Review projection, interactive Review UI, selected frame-region draft selection, source/runtime evidence drill-in, S4-aligned Review action semantics, evidence-backed suggestion review decisions and frame-to-condition patch affordance
- Known gaps: this screenshot is fixture product evidence, not a live installed-app clip. Per-run/session semantic recording binding, installed-app suggestion/Draft Preview handoff recording and live frame-to-condition recording remain open.

## Acceptance Notes

- The fixture review timeline renders event rows with before/after frame ids.
- The selected wait frame shows an OCR/source region box over the frame placeholder.
- The inspector shows the reviewed selected region with candidate kind, frame id, surface id and window-pixel bounds. `Draft Selection` uses the selected region as the review-only source for the generated condition patch, and the clear control removes the local selection/draft state without mutating a workflow.
- The inspector shows a frame-to-condition candidate with Save Patch and Preview Draft affordances, source/runtime decision, Source / Runtime / Diff evidence tiles, suggestion evidence refs, Accept / Reject controls, an accepted suggestion status, staged patch state, evidence-backed accepted-decision explanation and an undo review-decision control from the same `SemanticRecordingBundle` evidence ids.
- Accepted/rejected suggestion explanations use the shared S3/S4 action vocabulary (`review.acceptSuggestion`, `review.rejectSuggestion`) and mutation boundaries, so CLI suggestions and Review decisions cite the same evidence contract instead of parallel semantics.
- The real Review UI can be opened from Run Detail through `SemanticRecordingReviewPresenter`, which resolves safe artifact refs before SwiftUI receives artifact status.
- Source / Runtime / Diff tiles show safe refs in fixture mode and can show available/missing artifact status plus thumbnails when opened from a real bundle state.
- Review-generated draft patches can be previewed in `AutomationWorkflowDraftPreviewSheet` and imported only after user confirmation.
- Accepted suggestions explain the cited frame/artifact and staged patch operation inline, while still making Draft Preview import the required mutation boundary.
- Rejecting or undoing the accepted suggestion clears the staged patch that came from that suggestion, keeping review-only mutation state coherent.
- SwiftUI receives projection data and safe relative refs; it does not run Vision, AX, ScreenCaptureKit or raw file IO.
