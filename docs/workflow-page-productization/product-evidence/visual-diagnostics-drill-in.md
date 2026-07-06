# Visual Diagnostics Drill-In Artifact

- Capture date: 2026-07-06.
- Worktree note: local Owner 2 workflow UI/product-evidence pass, uncommitted mixed-owner worktree.
- Fixture: `AutomationRunState.ownerCFixture`, rendered through `workflow product-evidence snapshot visual-diagnostics-drill-in`.
- Output: `visual-diagnostics-drill-in.png`, 1440 x 1560 points at scale 2.
- User state: `Watch spinner disappearance` is selected, Run History has the completed `Condition matched` run expanded, and the run detail reads durable `AutomationTaskRun.conditionEvidence`.
- Proves: selected visual-condition runs can show observed summary, match outcome, sample count, watched region, similarity/threshold, diagnostic fields, two artifact image previews, Open/Reveal artifact actions, and inline artifact action feedback.
- Fixture artifacts: `fixture-artifacts/visual-condition/condition-last-sample.png` and `fixture-artifacts/visual-condition/condition-region-sample.png` are generated next to the screenshot and loaded through `AutomationConditionEvidenceArtifactPresenter`, the same safe artifact preview path used for App Support evidence refs.
- Known gaps: this is fixture evidence, not a live OCR/visual capture session recording. It proves the visual artifact action affordance/feedback state is visible, but not a real Finder/Preview interaction recording. Template/baseline previews remain future polish.
