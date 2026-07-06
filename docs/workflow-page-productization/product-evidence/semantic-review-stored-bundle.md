# Semantic Review Stored Bundle Evidence

Capture date: 2026-07-06
Worktree note: generated from local SparkleRecorder product-evidence snapshot command.
Command:

```bash
swift run SparkleRecorder workflow product-evidence snapshot semantic-review-stored-bundle --width 1680 --output docs/workflow-page-productization/product-evidence/semantic-review-stored-bundle.png
```

Evidence source: stored fixture bundle written to `docs/workflow-page-productization/product-evidence/fixture-semantic-review-stored-bundles/<recording-id>/`.
Fixture/source: `SemanticRecordingFixture.checkoutBundle()` persisted as `manifest.json` with deterministic PNG artifact refs, then rendered as `SemanticRecordingReviewState` with bundle directory and artifact statuses.
UI surface: `SemanticRecordingReviewFixtureView(state:)`.
Checklist item: S3 Review live bundle presenter path toward real Macro Review evidence drill-in.

What this proves:

- Macro Review can render from a stored bundle directory, not only from an in-memory fixture projection.
- Bundle Health appears before Teach System actions, showing manifest validation status, Available/Missing artifact counts and suppression count/detail.
- Source, Runtime and Diff evidence tiles show `Available` states and thumbnails from file-backed artifact refs.
- Candidate artifact actions are visible only when the presenter-style artifact status says the safe ref exists.
- Teach System candidates show `review.draftCandidate` with frame, source preview, source artifact and Draft Preview mutation boundary before the user creates a patch.
- The selected wait frame still supports review-only Draft Patch generation before Draft Preview import.

Known gaps:

- This is stored fixture evidence, not an installed-app live capture.
- It intentionally does not include a fake `.mov`, so Bundle Health honestly reports one missing artifact while PNG evidence is available; live `.mov` / keyframe bundle creation, live Open/Reveal recording, and confirmed Review -> Draft Preview import from a live bundle remain S2/S3 follow-up gates.
