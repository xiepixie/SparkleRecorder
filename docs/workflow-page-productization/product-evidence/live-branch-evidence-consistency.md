# Live Branch Evidence Consistency

- Capture date: 2026-07-06
- Worktree note: main ecd9ed63; dirty S0/S2/S3/S4 worktree with semantic recording and product-evidence changes
- App build/run source: /Applications/SparkleRecorder.app/Contents/MacOS/SparkleRecorder (App host PID 93314; window capture ID 1838)
- Workflow/package: S0 Branch Evidence Auto Live Gate (8BA26F05-035E-571B-BC47-53E3B7B628CC), imported from s0-branch-evidence-auto-workflow-draft.json; source run 72110AB6-A6C5-4F6F-BAD9-02332C127795 conditionNotMatched triggered target run 1D2408D1-29C0-459E-90A1-744E984A8FD7 conditionMatched through dependency 448AE69F-AFE7-5A22-8571-B029CF3CB039
- User action: Recorded live App-host handoff branch run payload and live App window capture after starting Source previous-outcome miss through workflow run --handoff app
- Checklist item: Live Branch Evidence Consistency (`live-branch-evidence-consistency`)
- Evidence source: live App-host handoff run payload and live App window capture assembled into reviewed MOV
- Clip file: `live-branch-evidence-consistency.mov`
- Sidecar file: `live-branch-evidence-consistency.md`
- Known gaps: Automated AX/input control was unavailable in this environment, so the clip proves durable branch runtime payload consistency and App-host execution; a richer manual Run Detail drill-in can still be recaptured later.

## Acceptance Notes

- This sidecar was completed from reviewed live capture metadata.
- Keep this sidecar next to the clip in `docs/workflow-page-productization/product-evidence/`.
- Re-run `swift run SparkleRecorder workflow product-evidence audit --require-live --json` before marking S0 complete.