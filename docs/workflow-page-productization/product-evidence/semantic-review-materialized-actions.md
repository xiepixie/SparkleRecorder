# Semantic Review Materialized Actions

- Capture date: 2026-07-06
- Evidence type: fixture product evidence
- Scenario command: `swift run SparkleRecorder workflow product-evidence snapshot semantic-review-materialized-actions --output docs/workflow-page-productization/product-evidence/semantic-review-materialized-actions.png`
- Source fixture: `SemanticRecordingFixture.checkoutBundle()`
- Patch source: `SemanticRecordingReviewDraftPatchBuilder` imageAppeared candidate from the checkout click frame
- UI surface: `SemanticRecordingReviewFixtureView`
- Screenshot file: `semantic-review-materialized-actions.png`
- Checklist item: S3 Review action semantics and materialized evidence alignment after Draft Preview handoff
- Worktree note: generated from the fixture snapshot command in the current dirty multi-owner worktree; the scenario input is deterministic fixture data.
- Known gaps: this screenshot is fixture product evidence, not a live installed-app clip. Live Run Detail -> Macro Review opening, Open/Reveal artifact interaction, suggestion accept/reject recording and confirmed import remain open.

## Acceptance Notes

- The fixture creates a Review-generated `imageAppeared` draft patch from the recorded checkout frame.
- The snapshot materializes that patch through `SemanticRecordingReviewAssetMaterializer`, producing package-local visual asset refs before rendering Review.
- The Review inspector renders `review.previewDraft` and `review.importDraft` rows with source artifact, package artifact, SHA-256 digest, draft task/condition and visual asset evidence.
- The action rows preserve the S3/S4 mutation boundary: preview requires Draft Preview, import mutates only after confirmation.
- This artifact proves the Review action contract can show post-materialization evidence; it does not claim live semantic recording capture or installed-app import completion.
