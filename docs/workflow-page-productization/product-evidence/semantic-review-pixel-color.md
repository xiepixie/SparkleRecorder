# Semantic Review Pixel Color

- Capture date: 2026-07-06
- Evidence type: fixture product evidence
- Scenario command: `swift run SparkleRecorder workflow product-evidence snapshot semantic-review-pixel-color --output docs/workflow-page-productization/product-evidence/semantic-review-pixel-color.png`
- Source fixture: `SemanticRecordingFixture.checkoutBundle()` plus a deterministic pixel sample source preview on the checkout confirmation frame
- UI surface: `SemanticRecordingReviewFixtureView`
- Screenshot file: `semantic-review-pixel-color.png`
- Checklist item: S3 Review pixel color picking -> `pixelMatched` draft patch affordance
- Worktree note: generated from the fixture snapshot command in the current dirty multi-owner worktree; the pixel sample is deterministic fixture data layered on the checkout bundle.
- Known gaps: this screenshot is fixture product evidence, not a live installed-app clip. Live pixel sampling from an installed semantic bundle and confirmed Draft Preview import remain open.

## Acceptance Notes

- The selected wait frame exposes a `Wait for pixel color` condition candidate sourced from a reviewed pixel sample.
- The Review inspector shows the color picker with the reviewed `#2BC66A` target color before workflow mutation.
- The staged draft patch is `pixelMatched`, references the pixel sample region, and still requires Draft Preview before import.
- This artifact proves the Review UI affordance and review-only draft state; it does not claim live semantic recording capture or installed-app product completion.
