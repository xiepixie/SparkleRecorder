# Branch Evidence Drill-In Artifact

- Capture date: 2026-07-06.
- Worktree note: local Owner 2 workflow UI/product-evidence pass, uncommitted mixed-owner worktree.
- Fixture: `AutomationRunState.ownerCFixture`, rendered through `workflow product-evidence snapshot branch-evidence`.
- Output: `branch-evidence-drill-in.png`, 1440 x 1120 points at scale 2.
- User state: `Wait for SLA window` selected with run `00000000-0000-0000-0000-00000000c406` expanded in Run History.
- Proves: Run Detail reads durable `AutomationTaskRun.branchEvidence` and shows persisted skipped/triggered branch decisions with reason, dependency, trigger, target join policy, and target run.
- Known gaps: this is a fixture screenshot rather than a live recording. S0 strict live gates are now covered by separate live clips; richer manual Run Detail branch drill-in can still be recaptured later if automated UI capture is available.
