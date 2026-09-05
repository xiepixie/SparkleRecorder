# Macro Reconstruction CLI Guide

Updated: 2026-09-04
Status: Implemented authoring interface; current verification and live acceptance pending

Use `SparkleRecorder reconstruction` to prepare a local evidence package, inspect candidate action IDs, and import a complete candidate. The implementation lives in `MacroReconstructionCLI.swift` and `MacroReconstructionPackage.swift`; this guide does not establish a passing build or installed-app acceptance. The active ledger is [19-reconstruction-product-implementation-plan.md](19-reconstruction-product-implementation-plan.md).

## Export a source package

Find the saved macro UUID through the existing `SparkleRecorder workflow macros --json` catalog, then run:

```sh
SparkleRecorder reconstruction export --macro-id <UUID> --output /absolute/path/reconstruction-package --json
```

The output directory must not already exist. Omitting `--output` creates a uniquely named `reconstruction-<macro UUID>-<UUID>` directory beneath the current directory. Export reads a complete accepted repository snapshot. If the macro links a semantic recording, that bundle must load so the package builder can evaluate privacy policy.

Visual bytes require explicit inclusion:

```sh
SparkleRecorder reconstruction export --macro-id <UUID> --output /absolute/path/reconstruction-with-video --include-video --json
```

`--include-video` requests permitted video and frames, together with available persisted observations. It does not upload anything or invoke a model. Missing artifacts produce warnings. Suppressed video is withheld unless verified full-file clock evidence supports the renderer's timing and the redaction receipt covers the required suppression ranges with a distinct artifact. Suppressed frames likewise require matching source and mask coverage. Missing clock provenance is reported; stream PTS alone does not prove movie/session alignment.

The package contains `source-macro.json`, `candidate-template.json`, `capabilities.json`, `reconstruction.json`, `manifest.json`, and `instructions.md`. `alignment.json` is present when provenance exists. Explicitly included artifacts and their SHA-256 values appear in the manifest. The source macro remains complete; package generation rejects source fields that still need known privacy sanitization. The actual movie container remains MOV or MP4 according to its artifact, rather than renaming MOV bytes.

## Author and inspect the complete candidate

Give the external author only the package/evidence you intend to share. Follow `instructions.md`, replace the complete candidate event/surface representation, and preserve `sourceRevision`. This CLI performs no model invocation and cannot certify which evidence an external author viewed.

After editing, list action IDs for either a standalone `SavedMacro` JSON file or the complete candidate document:

```sh
SparkleRecorder reconstruction inspect --macro /absolute/path/candidate.json --json
```

A positional file path is also accepted. Inspection uses strict playback-field decoding and `MacroActionReconstructor` with literal revision `candidate`. The returned action IDs belong in coverage targets; source IDs come from exported `reconstruction.json`. Inspection lists structural action identity; importing performs source-aware normalization and coverage validation.

Supported playback capabilities are the existing raw mouse/keyboard/scroll events and text locators, `waitForText`, and `verifyText`. No image, pixel, region-change, or stability event is added. `capabilities.json` lists numeric event kinds, accepted event/anchor fields, version and limits. Current limits include 100,000 events, a nondecreasing 24-hour timeline, explicit positive text deadlines up to 3,600 seconds, coordinate magnitude at most 1,000,000 and normalized coordinates in `[0, 1]`. Text verification remains a single observation.

Coverage includes every source action, including inferred fixed waits. Transformations reference actual candidate action IDs and provide reasons; noise removal has no replacement target. `unresolved` coverage and known `uncertainActionIDs` remain visible for review and can be tested, but acceptance requires explicit acknowledgement or correction. Input balance is checked over enabled events. Normalization preserves source identity, personalization, links, statistics, loops, speed, window-follow policy and chaining, then replaces candidate events/surfaces and refreshes caches.

## Import for review and testing

```sh
SparkleRecorder reconstruction import --macro-id <UUID> --candidate /absolute/path/candidate.json --json
```

Import returns a candidate UUID and normalized digest. It retains source and candidate revisions without replacing the accepted macro. A stale source revision, unsupported field, invalid input/geometry/deadline, missing coverage, or disallowed restored readable value is rejected.

Open **Refine** for the current library macro (or its reconstruction menu action). Review and test the candidate through the app. Test once executes one iteration without chained macros; acceptance retains the original repetition/chaining settings. Receipts bind that policy and exact tested content. Correcting a locator creates another immutable candidate and requires a fresh test. Playback completion, observable checks and user acceptance are separate decisions. This command family exposes no playback, success-receipt, acceptance, scheduling or restore command. Restoring the macro in the app does not undo external application actions.

`--json` uses the existing `sparkle.cli.result.v1` envelope; failures exit nonzero. Default output is a short text summary. `MacroReconstructionCLITests` supplies parser, literal candidate-ID, export/import and acceptance-gate fixtures; execution results remain in the central verification ledger.
