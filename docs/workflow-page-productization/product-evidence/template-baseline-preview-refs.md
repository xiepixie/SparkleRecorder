# Template/Baseline Preview Refs Artifact

- Capture date: 2026-07-06.
- Worktree note: local S0/S1 semantic-recording evidence pass, uncommitted mixed-owner worktree.
- Fixture: `SemanticRecordingFixture.checkoutBundle`, rendered through `workflow product-evidence snapshot template-baseline-preview-refs`.
- Output: `template-baseline-preview-refs.png`, 1440 x 980 points at scale 2.
- User state: the fixture evidence surface shows a source OCR region, a related image template, a runtime watched-region sample, and the preview comparison decision from the same `SemanticRecordingBundle`.
- Proves: S1's accepted source/runtime/comparison contract can be rendered as a user-readable evidence shape: Source Reference, Runtime Sample, Decision, related template, safe relative artifact refs, matcher score/threshold, reason, and traceable IDs.
- Boundary: this is fixture evidence, not a live recording review screen. It proves the product evidence shape for S0/S1 handoff; the final S3 Review UI still needs to render the same model inside the real Macro Review / Run Detail flow.
- Known gaps: S0 live-product gates are now covered by separate live clips; this fixture artifact still does not satisfy the real S3 Review UI source/runtime/decision drill-in requirement.
