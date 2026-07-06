# Failed Run Preview-Unavailable Artifact

- Capture date: 2026-07-06.
- Worktree note: local Owner 2 workflow UI/product-evidence pass, uncommitted mixed-owner worktree.
- Fixture: `AutomationRunState.ownerCFixture`, rendered through `workflow product-evidence snapshot failed-run-preview-unavailable`.
- Output: `failed-run-preview-unavailable.png`, 1440 x 1560 points at scale 2.
- User state: `Retry upload receipt` is selected, the failed attempt is expanded in Run History, and Run Evidence is auto-loaded from a fixture macro package whose screenshot file exists but is intentionally not decodable as an image.
- Proves: Run Detail keeps the verified per-run report, manifest binding, failed event, error text, and next-check guidance visible even when the screenshot preview cannot be decoded; the preview area falls back to `Screenshot preview unavailable` instead of failing the evidence section.
- Fixture evidence: `fixture-macros-preview-unavailable/00000000-0000-0000-0000-00000000C102.sparkrec/runs/00000000-0000-0000-0000-00000000C409/manifest.json`, `report.json`, and an unreadable `failure.png` are generated next to the product evidence and loaded through `AutomationTaskRunEvidencePresenter`.
- Known gaps: this is fixture evidence, not a live playback failure recording. Open Screenshot / Reveal Report interaction recording remains future evidence.
