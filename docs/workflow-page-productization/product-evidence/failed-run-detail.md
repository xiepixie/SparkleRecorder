# Failed Run Detail Artifact

- Capture date: 2026-07-06.
- Worktree note: local Owner 2 workflow UI/product-evidence pass, uncommitted mixed-owner worktree.
- Fixture: `AutomationRunState.ownerCFixture`, rendered through `workflow product-evidence snapshot failed-run-detail`.
- Output: `failed-run-detail.png`, 1440 x 1560 points at scale 2.
- User state: `Retry upload receipt` is selected, the failed attempt is expanded in Run History, and Run Evidence is auto-loaded from a fixture macro package.
- Proves: selected failed macro runs can show per-run evidence binding, verified manifest/report pairing, file action buttons near the binding, Reveal Report action feedback, failed event number, report error, report-derived next-check guidance, and an inline failure screenshot preview before the readiness checklist.
- Fixture evidence: `fixture-macros/00000000-0000-0000-0000-00000000C102.sparkrec/runs/00000000-0000-0000-0000-00000000C409/manifest.json`, `report.json`, and `failure.png` are generated next to the product evidence and loaded through `AutomationTaskRunEvidencePresenter`.
- Known gaps: this is fixture evidence, not a live playback failure recording. It does not prove preview-unavailable fallback or live Open Screenshot / Reveal Report interaction recording; it only proves the Run Detail action affordances and feedback state are visible in the product surface.
