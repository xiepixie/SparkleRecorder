# Task Reorder Authoring Evidence

- Capture date: 2026-07-06.
- Fixture: `AutomationRunState.ownerCFixture`, rendered through `workflow product-evidence snapshot task-reorder-authoring`.
- Output: `task-reorder-authoring.png`, 1440 x 940 points at scale 2.
- User action represented: moving existing task `Export report` to the insertion line between `Open nightly workspace` and `Verify dashboard text`.
- Checklist proof: existing task rows expose a drag source, row-between insertion line, visible moving-row state, and non-drag up/down controls in the same list surface. Reorder commits through `.upsertWorkflow`; the UI now also updates the moved task's graph position from neighboring projected nodes when possible.
- Known gaps: this is a deterministic fixture screenshot, not a real drag recording. A full live `.mov` / `.mp4` that captures macro drag-to-list, existing task reorder, connector drag-link, and post-drop mutation timing remains future evidence.
