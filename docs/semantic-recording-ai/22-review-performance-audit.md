# Review performance and acceptance audit

Updated: 2026-09-05
Status: Implemented; 836 tests / 104 suites and Swift 6 build passed

Scope: preserve the accepted reconstruction workflow while removing measured/structural hotspots and stale acceptance claims. Live recording evidence remains a separate gate.

## Findings and implemented changes

- Clock interpolation scans every anchor per action; geometry lookup scans every historical snapshot. Replace scans with validated binary searches, retaining gaps, shared endpoints, tolerance and per-surface semantics.
- Review video ticks scan action projections and publish on every tick. Index intervals and emit changes only when the active row or endpoint marker changes.
- SwiftUI materializes enumerated arrays and searches source rows for every coverage title. Use stable indexed collections and a precomputed ID-to-row map.
- Candidate JSON decoding and source reconstruction run on MainActor. Move value computation and file decoding to detached work; keep intents/observable publication on MainActor.
- Candidate import keeps old selected text and source row IDs; reset correction selection on new candidate and distinguish unusable/stale candidate status before test.
- Acceptance text still says capability binding/central verification are missing although code and 829 tests prove otherwise. Correct current evidence without closing live or external-AI gates.

## Validation

Existing clock/geometry/projector/review suites plus large deterministic lookup fixtures; compare the same workload before/after using elapsed timing for observation only, never as a flaky pass threshold. Test binary lookup boundary equivalence, quiet UI notifications, selection reset and import failures. Run full Swift Testing and Swift 6 build after targeted checks. Review actual fixture rendering.


## Measured result and accepted UX corrections

The identical Debug workload (18,000 anchors/snapshots; 6,000 paired lookups, construction excluded) took 10.010707083 s before and 0.004105750 s after on this machine. Results are checksum-validated. This is a query microbenchmark, not a capture FPS, UI frame-time or whole-app claim. Existing boundary tests and new interval/reference tests pass.

Review no longer publishes unchanged video ticks; 1,000 empty/unchanged ticks produce zero notifications. Source actions are reconstructed once in detached work. JSON file reads/decoding are detached, errors release busy state and preserve the selected candidate. New imports clear old corrections. Stale versions disable trial/acceptance; accepted versions clear the old comparison. Both columns show actual text input/targets, not just generic action names. Unmapped steps explicitly explain why video did not seek.

## Remaining issues, by actual scope

There are 47 unchecked checklist entries, including duplicated summary/detail gates. None is closed just because this optimization passes tests.

- **Live acceptance:** default-root ordinary recordings, measured one-frame/50 ms alignment, secure/excluded-context redaction, cleanup, moved-window/variable-latency playback, real correction→retest→accept and restart recovery still need authorized installed-app evidence.
- **External authoring:** actual video/frame inspection and semantic correctness of AI cleanup cannot be inferred from coverage reasons. No model invocation/inspection attestation exists.
- **Deferred functionality:** image-byte similarity, broader visual executable locators, checkpoint/resume preconditions and App Knowledge are not implemented by the current text-only reconstruction slice. Existing workflow visual conditions are a different vocabulary.
- **Performance not yet proven:** ScreenCaptureKit/Vision CPU/GPU load, dropped frames, memory under many large candidate versions and disk-export throughput require representative live profiling. The writer retains at most 18,000 alignment samples; later video may be unaligned. This is a known coverage limit, now paired with explicit step-level feedback, not evidence of full-session precision.
- **History storage:** candidate history currently loads complete immutable documents. This audit does not claim bounded memory for arbitrarily many 100,000-event versions; metadata pagination/lazy history is a separate repository contract change.

## Documentation corrections

The checklist and its executable gate mapping now name SCStream→AVAssetWriter rather than the replaced SCRecordingOutput implementation. Capability/test-policy/execution-digest binding is recorded as implemented; evidence hashes remain separate from external inspection attestation. Old S0–S4 live-gate pauses continue to apply to product evidence, not a ban on the accepted reconstruction engineering slice.

Final full suite: 836 tests / 104 suites passed. UI fixture rendering was exercised. The installed `/Applications/SparkleRecorder.app` (bundle version 94) also returns blocked Input Monitoring in its preflight-only command; no live recording or replay was performed. Source changes do not imply this installed bundle has been upgraded.

Swift 6 build passed after the final source changes. The offscreen fixture screenshot was inspected for layout; it captures the initial asynchronous refresh, so it does not establish live video or interactive responsiveness.
