# Macro Reconstruction Product Implementation

## Current code and verification posture

Product implementation and Review integration are complete in the feature branch. Full Swift Testing passed 829 tests in 102 suites; Swift 6 and Release builds passed. Offscreen fixture rendering verifies the Review layout. Installed-app live recording/reconstruction evidence remains unobserved: the local preflight is blocked by Input Monitoring permission.

| Boundary | Current code | Direct test mapping / remaining gate |
| --- | --- | --- |
| Capture provenance | Optional `RecordingReconstructionProvenance` stores monotonic origin/end, source/session mappings, bounded movie sample evidence, actual frame timing and measured geometry. Legacy bundles retain absent provenance. The app-owned AVAssetWriter records successful sample PTS rebasing and releases anchors only after finalized file-origin validation. A source event content digest prevents old video alignment from attaching to edited macros; legacy/mismatched source content is unavailable. | `RecordingReconstructionProvenanceTests`, existing clock/geometry/projection suites; live one-frame/50 ms proof pending. |
| Candidate Core | Full Codable authoring document, strict unknown-field decode, normalized SHA-256 identity, balanced input/geometry/deadline checks, complete source/real-target coverage and suppression checks. | `MacroCandidateValidatorTests`; passed in the complete suite. |
| Revision repository | Immutable source/candidate snapshots, safe digest filenames, atomic accepted pointer, pinned test tokens and normalized-content receipts; stale-base and uncertainty gates; original restore. | `MacroCandidateRepositoryTests`; fault-injection, stale-content, capability/test-policy receipts, one-iteration test and whole-snapshot checks passed. |
| Playback | Found/absent/unavailable text observations, bounded cancellation-aware waiting, conservative gesture locator cache. | `PlaybackTextObservationTests`, `PlaybackLocatorCacheTests`; both live adapters require installed-app verification. |
| Package / CLI | Local full-macro package and explicit visual inclusion; privacy/clock/receipt guards; `reconstruction inspect/export/import`. | `MacroReconstructionPackageTests`, `MacroReconstructionCLITests`; see [20-reconstruction-cli-guide.md](20-reconstruction-cli-guide.md). |
| Review | `MacroReconstructionReviewModel` consumes source/candidate actions and timing projections, imports/corrects candidates, and dispatches test/accept/restore through injected app/repository boundaries. | `MacroReconstructionReviewTests`; library Refine/card/compact entries wired; compare, text correction, cancellation and acceptance tested. Installed-app proof remains pending. |

### Accepted contract details

S1 accepts `MacroCandidateDocument.requiresAttention`: unresolved coverage or uncertain known action IDs may pass structural validation for testing; promotion separately requires acknowledgement or a corrected candidate. Candidate events/surfaces may differ broadly from source. Source loops, speed, window-follow policy, chaining and app-owned metadata remain protected. Executable identity includes source execution settings and surface matching data, excludes volatile statistics/caches/display names and behavior annotations, and conservatively retains readable event text that affects action reconstruction.

The capability manifest is `macro-candidate/v1`, supports macro version 3 and actual text playback only, and publishes numeric limits/field lists. Source action IDs use the source digest; candidate action IDs use literal `candidate`. Test receipts bind source revision, normalized executable digest, capability version, single-iteration test policy and the exact test execution digest. Test snapshots run once and exclude chained macros; acceptance preserves source repeat/chain settings. Current executable vocabulary has no image artifact references. Exported visual evidence has separate SHA-256 audit hashes; these are not proof that an external model viewed those artifacts.

S2 supplies provenance without fabricated video anchors. The package builder requires exact renderer-compatible clock coverage before supplying suppressed movie bytes, as well as matching source/current redaction coverage and distinct artifacts. Unverified or absent clock evidence remains a visible limitation. S3 consumes projected unavailable alignment; S4 performs local authoring export/import, with no model upload or unattended execution.

Resume/checkpoint precondition verification remains future work. Current recovery is restarting a candidate test or restoring an immutable original macro; it does not reverse external side effects.

Updated: 2026-09-04
Status: Product implementation verified; permission-dependent live acceptance open

Spec: [17-ai-assisted-macro-reconstruction-design.md](17-ai-assisted-macro-reconstruction-design.md). Foundation: [18-reconstruction-foundation-implementation-plan.md](18-reconstruction-foundation-implementation-plan.md).

## Scope and ownership

Continue through all four accepted delivery slices. Implement actual capture provenance, candidate validation/normalization, recoverable repository promotion, playback observation semantics, and Review/CLI authoring workflow. Live product gates require observed artifacts; code/tests cannot close them. Use existing CLI-first external AI authoring: export authorized evidence/instructions, import complete model-written candidate. Do not invent a model service or silently upload evidence.

| Owner | Exclusive files / boundary | Dependency |
| --- | --- | --- |
| Capture | SemanticRecordingBundle/Capture/Lifecycle, Recorder/SemanticRecorderBridge/LiveSemanticRecordingSession/ScreenCaptureKitSemanticCapture and new capture provenance helpers/tests | Existing clock/geometry foundation |
| Candidate Core | New MacroReconstructionCandidate.swift, MacroCandidateValidator.swift, MacroCandidateIdentity.swift and corresponding tests | SavedMacro/RecordedEvent, action reconstructor |
| Revision repository | MacroRepository.swift, new MacroCandidateStore.swift and repository tests | Candidate Core interface below |
| Coordinator | Playback observation adapter/core, Review/CLI package authoring and UI, integration tests, docs | Accepted owner APIs |

Agents do not edit shared owner files, commit, spawn helpers, or run simultaneous SwiftPM builds. Coordinator schedules red/green tests. Record accepted deviations here. All tests use Swift Testing, fake clients/clocks and temporary local fixtures; never live input/OCR or Application Support. Platform effects stay at the app edge; views dispatch model intents.

## Frozen candidate handoff

- `MacroCandidateDocument: Codable, Equatable, Sendable`: `macro: SavedMacro`, `sourceRevision: String`, `summary: String`, `coverage: [MacroCandidateCoverage]`, `uncertainActionIDs: [String]`, `model: String` with public defaulted initializer.
- `MacroCandidateCoverage: Codable, Equatable, Sendable`: `sourceActionID: String`, `disposition: MacroCandidateDisposition`, `candidateActionIDs: [String]`, `reason: String`.
- Disposition enum: preserved, merged, replacedByLocator, replacedByWait, removedAsNoise, unresolved.
- `MacroCandidateIdentity.revision(of: SavedMacro) throws -> String`: stable content digest of execution-affecting fields, ignoring volatile run statistics and display metadata. Same function identifies source and normalized candidate executable content.
- `MacroCandidateValidator.normalize(_ document: MacroCandidateDocument, source: SavedMacro) throws -> SavedMacro`: validates source revision, complete executable schema, input balance, finite bounded timing/coordinates/locator data, source-action coverage and real candidate action targets; returns source-protected metadata with candidate events/surfaces and refreshed caches. Source action IDs use document.sourceRevision; candidate action IDs use literal revision `candidate`.
- `MacroCandidateValidator.decode(_ data: Data) throws -> MacroCandidateDocument`: reject unknown playback-critical fields rather than Codable dropping them. Export capability manifest reflects only existing executable event/locator fields.
- No image/pixel/region event kinds added. First release exposes actual text capabilities and conservative source cleanup. Wider visual vocabulary remains a gated extension, as accepted in section 8.1.

## Tasks and acceptance

- [x] Capture persists optional backward-compatible provenance; old bundles are explicitly unavailable for precise reconstruction. Actual monotonic session start/end, source event mapping, sample PTS/geometry, and actual frame time replace fabricated equality. Live alignment uncertainty is honest.
- [x] Candidate decode, normalization, coverage audit and capability export pass malformed/unsupported/imbalanced/stale-source cases and broad valid rewrites.
- [x] Repository retains immutable source/candidate revisions; test receipts bind normalized content. Atomic accepted pointer rejects stale source, preserves metadata and references, pins loaded run data, and survives injected failures.
- [x] Playback observations distinguish nonmatch from unavailable; cancellation/deadlines and conservative locator reuse pass fake tests in both async/synchronous adapters.
- [x] Review can inspect synchronized action/video evidence, export an authorized AI package, import/correct a complete candidate, test via normal Player and accept/restore through repository intents.
- [x] CLI offers inspectable package/candidate operations without model upload or unattended execution.
- [ ] Integration review, complete tests, Swift 6 build and relevant local product checks pass; remaining live gates are explicitly recorded with evidence.

## Execution ledger

Started from b9fc7894b on codex/macro-reconstruction-foundation. Prior foundation: 46 new tests and 770 full tests passed. No live reconstruction gates closed yet.


### Final review corrections and usage decisions

- Read-only review caught unsafe source filenames, incomplete suppression checks, and clock-unverified video redaction. Regressions now pass; exports fail closed for incompatible redacted evidence.
- Changed source content disables evidence alignment even when event indices/timestamps match. Source identity is captured before session-time projection and legacy bundles remain unavailable.
- Stop cancels the full candidate task during target preparation. Shared Player reservations cover preparation, playback and deduplicated target cleanup; a stale cancellation cannot stop another run.
- Trial playback runs exactly one macro iteration, without chaining. This is explicit in Review and bound in the receipt; continuous source macros can therefore be evaluated without altering their accepted repeat setting.
- Review presents human action labels, counts, readable coverage explanations, uncertainty acknowledgement, conservative synchronized video markers, and fresh-test requirements after correction. English and Simplified Chinese strings use EditorUX.xcstrings.
- Package file copying runs off MainActor so large permitted videos do not freeze Review.
- See [21-reconstruction-review-ux.md](21-reconstruction-review-ux.md) for user flows and the remaining live checks.

Final command evidence: full tests 829/102; `swift build -Xswiftc -swift-version -Xswiftc 6` passed; `swift build -c release` passed (119.47 s); actual `reconstruction inspect --macro` against a temporary fixture returned `ok: true` with candidate action IDs. Preflight-only returned `blocked` for `inputMonitoring`; no live recording was attempted.
