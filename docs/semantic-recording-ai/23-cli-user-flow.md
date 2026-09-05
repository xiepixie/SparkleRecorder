# CLI guidance and user flow

Updated: 2026-09-05
Role: Implemented authoring UX contract; installed-app and live acceptance remain separate.

## User flow

The existing CLI exports a local evidence package, inspects candidate action IDs and imports an immutable candidate. Testing and acceptance happen in the app’s Refine interface. These are separate decisions: export does not invoke AI, import does not replace the accepted macro, and successful playback does not establish that the target app reached the intended outcome.

This slice adds discoverable `reconstruction`, `reconstruction --help`, and command-level `--help`. Help exits before repository access. JSON help adds an optional `usage` field to the existing result payload; other fields and the outer envelope remain compatible. Export directs users to instructions.md and candidate-template.json. Import identifies the next Refine/Test once step, states that the accepted macro is unchanged, and flags uncertainties requiring review.

S4 requests and accepts this additive CLI-only contract. S1 playback semantics and S3 acceptance policy remain unchanged. Direct tests: `MacroReconstructionCLITests.helpIsDiscoverableWithoutAccessingTheLibrary`, `summariesGuideTheNextUserDecision`, and the existing export/import source-preservation fixture.

## Verification

The CLI fixtures cover parser rejection, help without repository access, action IDs, export/import source preservation and acceptance requiring a test. Full Swift Testing and Swift 6/Release builds check the source integration. These checks do not establish live video alignment or the target app’s actual outcome.

## Integration boundary

This work is on `codex/reconstruction-review-performance`, alongside the previous indexed Review fixes. The primary workspace contains overlapping uncommitted UI work and is preserved. Until integrated and packaged, these changes are not present in the installed app.

Local evidence: 838 tests in 104 suites passed; explicit Swift 6 and Release builds passed. The built executable’s `reconstruction --help --json` returned a successful envelope containing the user-flow guide.
