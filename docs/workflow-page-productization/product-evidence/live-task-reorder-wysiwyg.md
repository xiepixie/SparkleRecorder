# Live Authoring WYSIWYG

- Capture date: 2026-07-06
- Worktree note: main 11e094d6; dirty parallel S0/S2/S3 worktree with live product evidence clip added
- App build/run source: /Applications/SparkleRecorder.app/Contents/MacOS/SparkleRecorder (running app pid 88510)
- Workflow/package: New workflow / 新建工作流 from local App repository; 3 tasks visible in Workflow page
- User action: Clicked the right inspector Down button for task 大贸易, verified the graph node and task list moved below 生产管理, then clicked Up to restore the original order
- Checklist item: Live Authoring WYSIWYG (`live-authoring-wysiwyg`)
- Evidence source: live App recording captured with macOS screencapture
- Clip file: `live-task-reorder-wysiwyg.mov`
- Sidecar file: `live-task-reorder-wysiwyg.md`
- Known gaps: Closes only the authoring WYSIWYG task reorder live gate; visual diagnostics, macro evidence, and branch evidence live gates are tracked by their own clips

## Acceptance Notes

- This sidecar was completed from reviewed live capture metadata.
- Keep this sidecar next to the clip in `docs/workflow-page-productization/product-evidence/`.
- Re-run `swift run SparkleRecorder workflow product-evidence audit --require-live --json` before marking S0 complete.
