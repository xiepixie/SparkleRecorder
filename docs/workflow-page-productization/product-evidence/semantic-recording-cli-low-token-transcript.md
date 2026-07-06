# Semantic Recording CLI Low-Token Transcript

- Capture date: 2026-07-07
- Evidence type: fixture CLI product evidence
- Source fixture: `SemanticRecordingFixture.checkoutBundle()`
- CLI output files: `/tmp/s4-maintenance-explain.json`, `/tmp/s4-maintenance-ocr.json`, `/tmp/s4-maintenance-visual.json`, `/tmp/s4-maintenance-suggest.json`, `/tmp/s4-maintenance-draft-from-recording.json`, `/tmp/s4-maintenance-validate.json`, `/tmp/s4-maintenance-simulate.json`, `/tmp/s4-maintenance-import-dry-run.json`
- Checklist item: S4 low-token CLI query flow over local visual index, plus fixture/review-only draft validation/simulation/import dry-run gates
- Worktree note: captured in the current dirty multi-owner worktree while S0/S2/S3 workstreams were still parallel; the scenario input is deterministic fixture data.
- Known gaps: this transcript is fixture CLI evidence, not live installed-app recording evidence. Product-ready default/live catalog, live/stored suggestion synthesis, image-byte visual similarity, live missing/deleted artifact status, and product-ready stored/live `workflow draft from-recording` remain open.

## Commands

```bash
swift run --scratch-path .build-test SparkleRecorder recording explain checkout-demo --fixture checkout --json
swift run --scratch-path .build-test SparkleRecorder recording ocr search checkout-demo --text "Order" --fixture checkout --json
swift run --scratch-path .build-test SparkleRecorder recording visual search checkout-demo --kind imageTemplateCandidate --label button --fixture checkout --json
swift run --scratch-path .build-test SparkleRecorder recording suggest conditions checkout-demo --fixture checkout --json
swift run --scratch-path .build-test SparkleRecorder workflow draft from-recording checkout-demo --fixture checkout --out /tmp/s4-maintenance-draft.json --json
swift run --scratch-path .build-test SparkleRecorder workflow draft validate /tmp/s4-maintenance-draft.json --json
swift run --scratch-path .build-test SparkleRecorder workflow draft simulate /tmp/s4-maintenance-draft.json --json
swift run --scratch-path .build-test SparkleRecorder workflow import /tmp/s4-maintenance-draft.json --dry-run --json
```

## Result Summary

| Command | Result | Evidence |
| --- | --- | --- |
| `recording explain` | `ok: true`; `keyPointCount: 3`; `visualEvidenceCount: 2` | Returns semantic key points, visual evidence summaries and the suppression note using ids and safe artifact refs. |
| `recording ocr search` | `ok: true`; `availability: deterministicFixture`; `count: 1` | Finds `Order confirmed` on frame `74000000-0000-0000-0000-000000000005` with artifact ref `visual-index/ocr/confirmation-region.png`. |
| `recording visual search` | `ok: true`; `count: 1` | Finds the `imageTemplateCandidate` labeled `button` / `primaryAction` with artifact ref `visual-index/templates/checkout-button.png`. |
| `recording suggest conditions` | `ok: true`; `availability: deterministicFixture`; `count: 1` | Suggests `Replace fixed wait with OCR confirmation`, confidence `0.86`, evidence count `1`, and mutation policy `Review required; no workflow or macro mutation until accepted.` |
| `workflow draft from-recording` | `ok: true`; writes `/tmp/s4-maintenance-draft.json` | Applies one `review.previewDraft` action with OCR evidence from frame `74000000-0000-0000-0000-000000000005`; the action is non-mutating and bounded by Draft Preview. |
| `workflow draft validate` | `ok: true`; `isValid: true`; `issueCount: 1` warning | The warning is `missingTimeoutBranch`, not a schema or import blocker. |
| `workflow draft simulate` | `ok: true`; `isSimulatable: true`; `steps: 1` | Simulates condition task `wait_order_confirmed_0000000e` as `conditionMatched`. |
| `workflow import --dry-run` | `ok: true`; `mode: dryRun`; `isImportable: true` | Builds an import plan without writing internal repository state. |

## Acceptance Notes

- The query flow returns compact summaries, ids, frame/event/observation refs, bounds and safe relative artifact refs.
- The flow does not emit image bytes, video bytes or whole-video payloads by default.
- Fixture warnings are present on fixture commands, so the output does not claim live product evidence.
- The generated draft still goes through validate, simulate and dry-run import before any confirmed import path can mutate workflow storage.
- Suggestions keep Review/Draft Preview as the mutation boundary; a separate S4 safety test now caps suggestions without evidence refs at low confidence.
