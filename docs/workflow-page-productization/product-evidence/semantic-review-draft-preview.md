# Semantic Review Draft Preview

- Capture date: 2026-07-06
- Evidence type: fixture product evidence
- Scenario command: `swift run SparkleRecorder workflow product-evidence snapshot semantic-review-draft-preview --output docs/workflow-page-productization/product-evidence/semantic-review-draft-preview.png`
- Source fixture: `SemanticRecordingFixture.checkoutBundle()`
- Patch source: `SemanticRecordingReviewDraftPatchBuilder` imageAppeared candidate from the checkout click frame
- UI surface: `AutomationWorkflowDraftPreviewSheet`
- Screenshot file: `semantic-review-draft-preview.png`
- Checklist item: S3 Review -> Draft Preview handoff with visual asset provenance before confirmed import
- Worktree note: generated from the fixture snapshot command in the current dirty multi-owner worktree; the scenario input is deterministic fixture data.
- Known gaps: this screenshot is fixture product evidence, not a live installed-app clip. Live Run Detail -> Macro Review opening, Open/Reveal artifact interaction, suggestion accept/reject recording and live frame-to-condition import remain open.

## Acceptance Notes

- The fixture path creates a Review-generated `imageAppeared` draft patch and applies it to a real `AutomationWorkflowDraftDocument`.
- Draft Preview runs the normal validation, simulation and dry-run import projection before rendering the sheet.
- The visual asset row shows package-local image path plus provenance badges for source frame id, crop bounds, source artifact path, surface id and SHA digest.
- The condition editor references the same region and image asset created by the Review patch, keeping frame-to-condition data visible before the user confirms import.
- This artifact proves the fixture Review -> Draft Preview provenance UI; it does not claim live semantic recording capture or installed-app product completion.
