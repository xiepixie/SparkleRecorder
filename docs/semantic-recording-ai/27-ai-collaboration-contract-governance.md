# AI collaboration contract governance

Updated: 2026-09-06
Status: active implementation contract

## Goal

Make reconstruction export, external AI authoring, package import, Candidate Draft editing, testing, acceptance, and playback share one explicit execution contract. The system must never require an external author or runtime fallback to guess a Playback Surface, package provenance, or contract version.

## Ownership boundaries

### Source context

`source-context.json` is the lightweight general source-Macro overview intended for an external AI author. Version v3 exposes source revision, Macro identity/version, event count/duration, protected playback facts, and minimized Playback Surface descriptions required to orient the reconstruction. Raw executable events are intentionally absent so they are not duplicated across overview files; `candidate-template.json` is the single exported raw-event baseline and is read only at draft time. The source context also omits local WindowServer/display IDs and capture timestamps in addition to Library personalization, notes/tags/favorites, hotkeys, statistics, local semantic-recording references, cache fields, and chained Macro identity.

### Reconstruction package provenance

A directory import is a reconstruction package, not an alias for `candidate.json`. Current package v4 uses `harness.json` as the small entry/version ledger and `authoring-contract.json` as the complete machine-readable executable/enum/rule contract. Import requires those files plus `manifest.json`, `source-context.json`, `reconstruction.json`, `candidate-template.json`, and `candidate.json`; it re-projects action context from the system-maintained template events before repository insertion so mixed/tampered package files are rejected. Real CLI/Review import also regenerates the source overview and strict system candidate template from the current accepted Source Revision, preventing external tools from modifying those App-owned files while preserving the same revision label. Manifest-listed evidence artifacts are path-confined and verified with streaming SHA-256 before their provenance is retained. The resulting immutable Candidate retains machine-readable package provenance. A standalone `candidate.json` remains supported, but is explicitly marked as lacking package provenance. A dedicated v3 compatibility adapter accepts the prior `contract.json` / `capabilities.json` / `authoring-policy.json` layout without making new exports reproduce it.

### Playback Surfaces and editor rebinding

Playback Surface identity/geometry is source-owned for external AI authoring. `macro-candidate/v4` omits `macro.surfaces` from new external candidate JSON; AI may choose among existing surfaces only through `event.surfaceId`, using `source-context.json` / `reconstruction.json` for read-only context. It may not invent or rewrite live window identity.

Candidate Editor is the app-owned rebinding seam. Rebinding is per `surfaceID`, never "replace all surfaces". A user editing a multi-surface Candidate can see every known surface, identify which surfaces are used by the current selection, rebind one surface without changing the others, and remove only an unreferenced surface. Removing a surface still referenced by any event is rejected instead of producing a dangling executable reference.

The ordinary accepted-Macro editor follows the same per-surface model so Candidate and accepted revisions do not expose contradictory window-binding semantics.

### Contract versions

All reconstruction contract versions are owned by `MacroReconstructionContractVersions` in Core. The current set is package `macro-reconstruction-package/v4`, harness `macro-reconstruction-harness/v1`, authoring contract `macro-reconstruction-authoring/v1`, candidate capability `macro-candidate/v4`, source context `macro-reconstruction-source/v3`, action context `macro-reconstruction-action-context/v3`, authoring policy `macro-reconstruction-policy/v1`, and candidate action revision `candidate`.

`harness.json` carries the current version ledger and staged reading plan; detailed event/action enum vocabulary, authoring policy and validator-facing rules live once in `authoring-contract.json`. Package import validates every required version before accepting `candidate.json`. Version changes that alter executable or authoring semantics invalidate old test receipts and require re-export/regeneration unless an explicit compatibility adapter exists.

## UX contract for multi-surface editing

The Target Windows section shows all Playback Surfaces in stable surface-ID order. Each row shows application/title, recorded frame size, and whether the current selection uses that surface. Actions are explicit:

- **Rebind…** changes only that surface ID.
- **Remove** is enabled only when no event references that surface.
- If selected actions refer to exactly one surface, that row is marked as selected and its **Rebind…** action targets that ID directly.
- If selected actions span multiple surfaces, the UI explains that each surface must be rebound independently; it never picks the first surface.
- Adding a new surface is a separate operation and does not rewrite existing event `surfaceId` values automatically.

No editor action silently migrates events between surfaces. Changing an event's `surfaceId` remains an explicit action-level edit.

## Acceptance checks

1. A multi-surface Candidate can rebind `surface-2` while preserving `surface-1` byte-for-byte.
2. Removing a referenced surface is rejected; removing an unused surface succeeds.
3. Ordinary Macro and Candidate Editor use the same per-surface mutation semantics.
4. Package import rejects missing/mismatched contract metadata before Candidate storage.
5. A copied `candidate.json` from another package is rejected by source revision/provenance checks.
6. `source-context.json` contains no raw event stream, Library personalization, local evidence references, WindowServer/display IDs, or capture timestamps.
7. The package exports exactly one raw event baseline (`candidate-template.json`), while `reconstruction.json` supplies compact action semantics for action-first triage.
8. Candidate Editor saves inherit package provenance.
9. Valid v3 packages remain readable through the compatibility adapter; new v4 exports use only the layered Harness layout.
10. CLI/Review import rejects changes to system-maintained Harness/source/template files and rejects manifest artifact hash mismatches while allowing the AI-authored `candidate.json` to change.
11. Full Swift Testing, Swift 6 Debug, Release, and `git diff --check` pass.
