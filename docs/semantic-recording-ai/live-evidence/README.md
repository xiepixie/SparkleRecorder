# Semantic Recording Live Evidence

更新时间：2026-07-07
状态：evidence intake directory; no live gate is closed by files in this directory alone

This directory is the landing zone for future S2 live semantic recording evidence. It is intentionally empty of accepted live artifacts until an authorized macOS 15+ machine records them.

Use [../15-s2-live-evidence-playbook.md](../15-s2-live-evidence-playbook.md) as the source of truth before adding anything here. A file in this directory is evidence only when its sidecar explains what was captured, which checklist gate it supports, what command or app path produced it, and which gates remain open.

## Expected Run Layout

Create one subdirectory per reviewed run:

```text
docs/semantic-recording-ai/live-evidence/<yyyy-mm-dd-scenario>/
```

Recommended filenames:

```text
s2-preflight.md
s2-live-smoke.md
s2-live-smoke.json
s2-live-smoke-synthetic-redaction.md
s2-recorder-bridge.md
s2-recorder-bridge.mov
s2-suppression-redaction.md
s2-cleanup.md
s2-root-id-policy.md
s3-linked-review.md
s3-frame-to-condition.mov
s4-live-query.md
```

Large bundles should be referenced by path and summarized with manifest path, recording id, sidecar paths, readiness status, counts, hashes where useful, and privacy notes. Do not commit sensitive unredacted video, empty placeholder videos, empty bundle directories, or sidecars with unfinished required fields.

## Evidence Rules

Accepted evidence must name:

- checklist item or gate group
- commit or dirty worktree note
- macOS version and app build/run source
- target app/window
- permissions and experimental settings
- command or installed-app user path
- produced bundle directory and manifest path when applicable
- readiness status, persisted reload status and known gaps
- privacy/suppression/redaction notes
- explicit statement of which gates remain open

Markdown sidecars in run subdirectories must include these exact labels so the executable audit can distinguish reviewed evidence from placeholders:

```text
Checklist item:
Gates remain open:
```

Not accepted as live-product proof:

- fixture evidence
- blocked preflight evidence without a later finished bundle
- explicit temp bundle path only
- synthetic redaction rehearsal only
- tests that never touch live ScreenCaptureKit, Vision, AX or app UI
- docs that describe intended behavior without saved artifacts
- renamed non-video files, zero-byte clips or unknown-size clips
- root-level evidence files outside a reviewed run directory

## Gate Mapping

| Gate | Evidence Expected Here | Still Not Enough By Itself |
| --- | --- | --- |
| S2 authorized live bundle | `s2-live-smoke.md`, optional JSON, real `.mov`, keyframe refs, sidecars, persisted reload/readiness notes | keyframes-only run, manifest-only bundle, or in-memory finish counts |
| S2 ordinary Recorder bridge | `s2-recorder-bridge.md` plus clip/screenshots proving app preflight, normal stop, saved macro and `SavedMacro.semanticRecording` | manually selecting a bundle in Review |
| S2 safety/privacy/cleanup | suppression/redaction/cleanup sidecars or clips with reviewed privacy notes | pure tests or synthetic redaction only |
| S2 root/id policy | `s2-root-id-policy.md` documenting default root, recording id policy and explicit-path deprecation point | explicit `--bundle-path` proof |
| S3 installed-app Review | `s3-linked-review.md` showing saved-macro-linked bundle opens through presenter with Bundle Health / Run Target / Open-Reveal feedback | fixture/stored Review snapshots |
| S3 frame-to-condition | `s3-frame-to-condition.mov` proving live OCR/image/region/pixel candidate creation and Draft Preview handoff | fixture patch tests only |
| S4 product-ready live query | `s4-live-query.md` with default-root CLI outputs over accepted S2 bundles and safe refs only by default | explicit stored-bundle reads or unavailable suggestions |

When a gate is accepted, update:

1. [../acceptance-checklist.md](../acceptance-checklist.md)
2. [../06-current-work-and-next-tasks.md](../06-current-work-and-next-tasks.md)
3. [../14-s0-s4-final-gap-alignment.md](../14-s0-s4-final-gap-alignment.md)
4. [../workstreams/s2-app-capture-visual-index.md](../workstreams/s2-app-capture-visual-index.md)
5. S3 or S4 workstream docs if the accepted evidence unblocks that owner
