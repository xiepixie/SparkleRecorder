# Playback and presentation reliability audit

Updated: 2026-09-05
Role: Active bugfix ledger; live user-reported playback failure is not yet declared resolved.

Evidence: selected macro has 23 keyboard/flags events, one Chrome surface and an empty runs directory. The editor and Review can decode its actions. Manual playback only closes NSPopover, does not hide the standalone library, bypasses the shared target application preparation client, and never saves successful run evidence. Aborted completion returns without replacing the Playing status. Post-event permission is defined in PermissionCenter but unused by playback. Installed CLI preflight reports denied Accessibility/Input Monitoring; this is supporting evidence, not proof of the GUI process's effective post-event permission.

Fix boundary: use shared prepared playback for manual runs, preserve stop/cancellation and chaining, check post-event permission before preparation/execution through an injected app-edge client, and surface rejected/failed outcomes. Record successful manual runs through existing evidence persistence. Preserve source buffers across selection/loading. UI work removes measured structural main-thread IO/decoding and prevents loading from trapping dismissal.

Validation: fake permission/target/player clients; shared playback/runtime and recording pipeline suites; full Swift Testing and Release packaging. Actual target-app behavior requires a controlled live replay; do not run arbitrary recorded shortcuts into the user's application to manufacture a pass.


Implemented: manual playback now uses AutomationScheduledMacroPreviewClient/AutomationPlayerClient target preparation, receipts and success evidence. It hides the library before activating/launching the target, announces Playing only after startup is accepted, exposes failure, supports cancellation during preparation, and preserves chain-cycle detection. Review trials hide then restore the app. GUI Player/automation and CLI entrypoints check post-event permission. Selected-macro history opens that macro’s latest run; workflow-wide history remains in automation. Buffered events are persisted only when owned by the selected macro and not loading.

Performance: review bundle validation and file scans now run detached; image previews decode/downsample off main to at most 1024 pixels. Initial Review loading retains an available Close/Esc action and cancels publication after dismissal. No arbitrary animation delay or global FPS claim is introduced.

Validation before final packaging: 843 tests / 106 suites passed. Permission rejection and rejected-start presentation have explicit fake-client tests; existing cancellation/reservation/target preparation, recording pipelines and complete regression suites also pass. No arbitrary user macro was replayed against Chrome during diagnosis.

GUI observation: the installed app’s Settings > System permissions showed Accessibility, Input Monitoring and Screen Recording all authorized. The CLI denial must not be represented as proof that GUI playback lacked permission. Missing hide/target-preparation and outcome handling are independently confirmed code defects.

## Foreground correction after build 103

User confirmed hiding worked but Chrome was not raised. The old preparation only called `activate()` and checked window existence. Apple documents activation as a request, not a guarantee. The revised path yields activation before hiding, restores and raises the resolved bound AX window, and waits for both active application and matching focused window before allowing playback. Failure is explicit and no playback starts. Manual and Review hide only after the prepared handoff; unbound playback keeps its prior behavior. Platform handles remain MainActor-owned; bounded readiness/cancellation sequencing has pure fake-client tests.

Reference: [Apple cooperative activation](https://developer.apple.com/documentation/appkit/passing-control-from-one-app-to-another-with-cooperative-activation).
