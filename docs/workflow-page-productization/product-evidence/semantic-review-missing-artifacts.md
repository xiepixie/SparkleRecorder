# Semantic Review Missing Artifacts Evidence

Capture date: 2026-07-06
Worktree note: generated from local SparkleRecorder product-evidence snapshot command.
Command:

```bash
swift run SparkleRecorder workflow product-evidence snapshot semantic-review-missing-artifacts --output docs/workflow-page-productization/product-evidence/semantic-review-missing-artifacts.png
```

Evidence source: stored fixture bundle written to `docs/workflow-page-productization/product-evidence/fixture-semantic-review-missing-artifacts/<recording-id>/`.
Fixture/source: `SemanticRecordingFixture.checkoutBundle()` persisted as `manifest.json` with frame PNGs present and source/runtime/diff/candidate artifact files intentionally omitted.
UI surface: `SemanticRecordingReviewFixtureView(state:)`.
Screenshot file: `semantic-review-missing-artifacts.png`
Checklist item: S3 Review missing/deleted artifact drill-in and S4 evidence status alignment.

What this proves:

- Macro Review still opens from a stored bundle when referenced source/runtime/diff artifact files are missing.
- Bundle Health summarizes missing refs before Teach/Draft actions, so users see evidence readiness before creating or importing a patch.
- Candidate and Source/Runtime/Diff evidence rows show `Missing file` instead of hiding the evidence ref or silently dropping Open/Reveal affordances.
- The candidate still shows `review.draftCandidate` with the original source artifact ref and Draft Preview mutation boundary, making the missing file a visible evidence status rather than a different action semantic.
- Missing rows explain that Open/Reveal is unavailable and point to retention, delayed writes or omitted sidecars as likely causes.
- The Review action contract remains visible, so missing artifact status is evidence context, not a hidden workflow mutation.

Known gaps:

- This is stored fixture evidence, not an installed-app live capture.
- It does not prove a real retention cleanup deleted these files; it proves the Review UI degradation path once the presenter reports missing files.
