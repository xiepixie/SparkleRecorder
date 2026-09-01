# Documentation Guide

Updated: 2026-08-25

Role: Current reference.

## Start here

1. Read [`DOCUMENTATION_STATUS.md`](DOCUMENTATION_STATUS.md) for the current implementation and active workstreams.
2. Choose the relevant workbench: [`automation-engine/`](automation-engine/README.md), [`workflow-page-productization/`](workflow-page-productization/README.md), or [`semantic-recording-ai/`](semantic-recording-ai/README.md).
3. Treat [`archive/`](archive/README.md) as historical context only.

## Required document header

New planning/reference documents use:

```markdown
# Title

Updated: YYYY-MM-DD

Role: Current reference | Active plan | Workstream | Archived snapshot.
```

Existing large workbenches may adopt the header incrementally, but every newly created document must use it.

## Naming and structure

- `README.md`: scope, navigation, current boundary, and non-goals.
- `00-current-status.md`: concise current facts and blockers, not a chronological diary.
- `NN-topic.md`: stable design or contract topic.
- `workstreams/<owner-or-slice>.md`: active ownership and handoff ledger.
- `acceptance-checklist.md`: evidence-backed completion gates.
- `archive/progress/YYYY-MM-DD-*.md`: frozen progress snapshots.
- `archive/references/*.md`: superseded reference material retained for history.

## Status and evidence rules

- Use the shared vocabulary defined in [`DOCUMENTATION_STATUS.md`](DOCUMENTATION_STATUS.md).
- Planned types and interfaces must be labeled proposed until accepted in owner docs and direct tests.
- “Done” requires implemented code and relevant tests; UI/product completion also requires the documented product evidence.
- Keep future gaps explicit. Never imply OS wakeup, live evidence, or background execution exists because a projection or fixture exists.
- Prefer updating a current status table over appending dated addenda.

## Archiving workflow

1. Confirm the document is superseded or historical.
2. Move it with `git mv` into `archive/progress/` or `archive/references/`.
3. Add or retain an archive banner explaining its date and replacement.
4. Update active links and [`archive/README.md`](archive/README.md).
5. Run the repository Markdown link checks and `git diff --check`.
