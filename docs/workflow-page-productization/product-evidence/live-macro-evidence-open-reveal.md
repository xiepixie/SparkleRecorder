# Live Macro Evidence Open/Reveal

- Capture date: 2026-07-06
- Worktree note: main 9b8d14f2; dirty parallel S0/S2/S3/S4 worktree with semantic recording and product-evidence changes
- App build/run source: /Applications/SparkleRecorder.app/Contents/MacOS/SparkleRecorder App host PID 56966; CLI .build/debug/SparkleRecorder uses repository-backed workflow history
- Workflow/package: S0 Macro Evidence Live Gate (D0DE2C1D-3487-5582-8C28-3D973F632261), task Intentional point-resolve failure (0E3A1031-7598-50CA-AA93-FAFB9F177069), macro C0D3AA10-0000-4000-8000-000000000E01, failed run/evidence 6C7D7143-D4AB-4C4F-AAC4-BBEB7D3B6B29 with report.json manifest.json failure.png under the per-run macro evidence directory
- User action: Used the live App-host failed macro run payload, opened failure.png, and attempted reveal of report.json after the Intentional point-resolve failure run had written per-run evidence
- Checklist item: Live Macro Evidence Open/Reveal (`live-macro-evidence-open-reveal`)
- Evidence source: live App-host failed macro run payload with per-run report manifest screenshot and macOS Open Reveal file-action capture
- Clip file: `live-macro-evidence-open-reveal.mov`
- Sidecar file: `live-macro-evidence-open-reveal.md`
- Known gaps: The clip records the live failed run payload, per-run report/manifest/screenshot, Preview open result and App window context; automated AX/input button clicking was unavailable in this environment, so the file actions were invoked through macOS Open/Reveal rather than by manually clicking the Run Detail buttons.

## Acceptance Notes

- This sidecar was completed from reviewed live capture metadata.
- Keep this sidecar next to the clip in `docs/workflow-page-productization/product-evidence/`.
- Re-run `swift run SparkleRecorder workflow product-evidence audit --require-live --json` before marking S0 complete.