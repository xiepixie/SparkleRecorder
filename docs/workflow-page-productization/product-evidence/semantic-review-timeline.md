# Semantic Review Timeline

- Capture date: 2026-07-06
- Evidence type: fixture product evidence
- Scenario command: `swift run SparkleRecorder workflow product-evidence snapshot semantic-review-timeline --output docs/workflow-page-productization/product-evidence/semantic-review-timeline.png`
- Source fixture: `SemanticRecordingFixture.checkoutBundle()`
- Projection: `SemanticRecordingReviewProjection`
- UI surface: `SemanticRecordingReviewFixtureView`
- Screenshot file: `semantic-review-timeline.png`
- Checklist item: S3 fixture Review projection, interactive Review UI and frame-to-condition patch affordance
- Known gaps: this screenshot is fixture product evidence, not a live installed-app clip. Live run/macro -> bundle auto-binding, frame crop file copy/package materialization, pixel color picking UI and live frame-to-condition recording remain open.

## Acceptance Notes

- The fixture review timeline renders event rows with before/after frame ids.
- The selected wait frame shows an OCR/source region box over the frame placeholder.
- The inspector shows a frame-to-condition candidate with Save Patch and Preview Draft affordances, source/runtime decision and review-only suggestion policy from the same `SemanticRecordingBundle` evidence ids.
- The real Review UI can be opened from Run Detail through `SemanticRecordingReviewPresenter`, which resolves safe artifact refs before SwiftUI receives artifact status.
- Review-generated draft patches can be previewed in `AutomationWorkflowDraftPreviewSheet` and imported only after user confirmation.
- SwiftUI receives projection data and safe relative refs; it does not run Vision, AX, ScreenCaptureKit or raw file IO.
