# Live Visual Diagnostics Open/Reveal

- Capture date: 2026-07-06
- Worktree note: main 9b8d14f2; dirty parallel S0/S2/S3/S4 worktree with semantic recording and product-evidence changes
- App build/run source: /Applications/SparkleRecorder.app/Contents/MacOS/SparkleRecorder App host PID 56966; CLI .build/debug/SparkleRecorder triggered handoff command B225F715-EA79-4A53-B26D-750655919B1E
- Workflow/package: S0 Visual Diagnostics Live Gate (2C980835-BC46-577F-8B7A-AD74ED57A20C), task OCR diagnostic sample miss (E23A345A-C718-5392-9053-B2786B82C19D), run 4C6EF768-CD54-4779-8FAE-4C6DFD6077C9, artifacts under ~/Library/Application Support/SparkleRecorder/AutomationEvidence/4C6EF768-CD54-4779-8FAE-4C6DFD6077C9
- User action: Triggered the OCR diagnostic task through workflow run --handoff app, confirmed conditionEvidence with last-sample and watched-region PNG artifacts, opened condition-last-sample.png, and attempted reveal of condition-region-sample.png
- Checklist item: Live Visual Diagnostics Open/Reveal (`live-visual-diagnostics-open-reveal`)
- Evidence source: live App-host OCR condition run payload with App Support condition artifacts and macOS Open Reveal file-action capture
- Clip file: `live-visual-diagnostics-open-reveal.mov`
- Sidecar file: `live-visual-diagnostics-open-reveal.md`
- Known gaps: The clip records the live App-host payload, persisted App Support artifacts, Preview open result and App window context; automated AX/input button clicking was unavailable in this environment, so the file actions were invoked through macOS Open/Reveal rather than by manually clicking the Run Detail buttons.

## Acceptance Notes

- This sidecar was completed from reviewed live capture metadata.
- Keep this sidecar next to the clip in `docs/workflow-page-productization/product-evidence/`.
- Re-run `swift run SparkleRecorder workflow product-evidence audit --require-live --json` before marking S0 complete.