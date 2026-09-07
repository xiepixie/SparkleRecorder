# SparkleRecorder Documentation Status

Updated: 2026-09-06

This is the authoritative documentation index. Code and direct tests remain the source of truth for implementation claims; plans describe future work unless they link to accepted implementation evidence.

## Status vocabulary

| Status | Meaning |
| --- | --- |
| **Current reference** | Describes implemented architecture or supported user behavior. |
| **Active plan** | Approved direction with unfinished work; must not be described as implemented. |
| **Workstream** | Current execution ledger with owners, blockers, and acceptance evidence. |
| **Archived snapshot** | Historical context only; dates and progress claims are frozen. |

All new or materially updated planning documents must include an `Updated: YYYY-MM-DD` line and state their role. Superseded progress ledgers move to `docs/archive/`; they are not edited to resemble current state.

## Current implementation snapshot

| Area | Status | Current source of truth | Remaining product gap |
| --- | --- | --- | --- |
| Swift 6 and Swift Testing | Current reference | `Package.swift`, `Tests/SparkleRecorderTests/` | Keep all new tests on Swift Testing. |
| Recording and playback engines | Current reference, first-pass boundaries | `Sources/SparkleRecorderCore/Recording*`, `Playback*`, corresponding tests | Continue extracting reusable behavior from app lifecycle shells. |
| Automation reducer/runtime | Current reference, first pass | `docs/automation-engine/`, `AutomationContract.swift`, `AutomationReducer.swift`, runtime/client tests | Background wakeup, richer resource policy, and push progress remain open. |
| Workflow UI | Active productization | `docs/workflow-page-productization/` | Quick scheduling, execution-level Run Center, evidence recovery, and live product acceptance remain open. |
| Schedule readiness | First local slice implemented | `AutomationWorkflowActivationProjection`, `AutomationWorkflowActivationCard`, projection tests | Permission/macro capability checks, presets, pause semantics, and background scheduling remain open. |
| Semantic recording and AI | Active gated workstream | `docs/semantic-recording-ai/README.md`, its current workstreams and acceptance checklist | Authorized live evidence gates remain open; CLI-first/MCP-deferred boundary remains in force. |

## Documentation map

| Path | Role | Use |
| --- | --- | --- |
| [`../CONTEXT.md`](../CONTEXT.md) | Current domain glossary | Canonical terms and relationships for Macro, Recorded Event, Playback Surface, Text Anchor, Text Target, Candidate, and Source Revision. |
| [`README.md`](README.md) | Current reference | Documentation conventions, lifecycle, and archive rules. |
| [`SparkleRecorderArchitecture.md`](SparkleRecorderArchitecture.md) | Current reference | Product and architecture orientation; validate detailed claims against code. |
| [`automation-engine/README.md`](automation-engine/README.md) | Active engine workbench | Reducer, adapters, persistence, scheduling, UI contracts, and tests. |
| [`workflow-page-productization/README.md`](workflow-page-productization/README.md) | Active product UX workbench | Workflow UI, scheduling/run/evidence UX, and product evidence. |
| [`semantic-recording-ai/README.md`](semantic-recording-ai/README.md) | Active gated workbench | Semantic recording, Review, live evidence, and CLI/AI boundaries. |
| [`semantic-recording-ai/17-ai-assisted-macro-reconstruction-design.md`](semantic-recording-ai/17-ai-assisted-macro-reconstruction-design.md) | Accepted design; automated implementation verified | Capture provenance, candidate/revision, text-observation, package/CLI and Review work map to direct tests in plan 19; automated verification passes; live acceptance remains open. |
| [`semantic-recording-ai/19-reconstruction-product-implementation-plan.md`](semantic-recording-ai/19-reconstruction-product-implementation-plan.md) | Active implementation ledger | Frozen owner contracts, current code/test mapping and remaining acceptance gaps. |
| [`semantic-recording-ai/22-review-performance-audit.md`](semantic-recording-ai/22-review-performance-audit.md) | Current performance and acceptance audit | Indexed Review lookups, UX state fixes, 836 passing tests, Swift 6 build, and outstanding live/performance evidence. |
| [`semantic-recording-ai/23-cli-user-flow.md`](semantic-recording-ai/23-cli-user-flow.md) | Current CLI reference | Discoverable help, export/import next-step guidance and app Review handoff. |
| [`semantic-recording-ai/24-playback-reliability-audit.md`](semantic-recording-ai/24-playback-reliability-audit.md) | Playback repair ledger | Manual/shared execution handoff, permission/error handling, latest macro run and presentation load fixes. |
| [`semantic-recording-ai/25-recording-track-and-candidate-contract.md`](semantic-recording-ai/25-recording-track-and-candidate-contract.md) | Current implementation contract | Strict candidate authoring projection, deterministic continuous-scroll compaction, playable/evidence track separation, evidence sidecar persistence, and final playable digest ownership. |
| [`semantic-recording-ai/26-robust-reconstruction-evidence-audit.md`](semantic-recording-ai/26-robust-reconstruction-evidence-audit.md) | Current evidence/robustness audit | Capture intensity and scope, stable window identity, degraded visual evidence, mechanical-evidence export, AI authoring objectives, and remaining image-locator/cross-display gaps. |
| [`semantic-recording-ai/27-ai-collaboration-contract-governance.md`](semantic-recording-ai/27-ai-collaboration-contract-governance.md) | Current AI collaboration contract | Minimal source context, package provenance import, per-Surface editor rebinding, and centralized reconstruction contract versions. |
| [`semantic-recording-ai/20-reconstruction-cli-guide.md`](semantic-recording-ai/20-reconstruction-cli-guide.md) | Current authoring interface; automated verification passed | Local full-file export, candidate action inspection and import; explicit visual inclusion and app-owned testing/acceptance. |
| [`MacroEditorUserGuide.zh-Hans.md`](MacroEditorUserGuide.zh-Hans.md) | Current user guide | Macro Editor behavior that is implemented and user-facing. |
| [`archive/README.md`](archive/README.md) | Archive index | Superseded plans, progress ledgers, and historical references. |

## Current priorities

1. Continue the scheduler/run/evidence UX from its accepted activation-projection slice: capability contract and fixtures first, then quick schedule, Run Center, and evidence recovery.
2. Keep the App-online scheduling limitation visible until a separately accepted background lifecycle implementation has live evidence.
3. Complete authorized S2/S3/S4 live acceptance and representative recording/review profiling; reconstruction code verification is complete, while physical product evidence remains open.
4. Update this index when a capability changes status; do not append dated progress paragraphs here.

## Maintenance rules

- One current status index: this file.
- One README per active workbench, linking to its current status, contracts, workstreams, and acceptance checklist.
- Progress history belongs in Git and `archive/progress/`, not as an ever-growing preamble in current docs.
- Archived files may contain stale paths and historical assertions; their archive banner governs.
- A checked acceptance item needs direct evidence. An unverified plan stays unchecked.
- When moving a document, update active Markdown links and the archive index in the same change.
