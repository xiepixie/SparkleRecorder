import Cocoa
import SparkleRecorderCore
import SparkleRecorderTooling

enum WorkflowProductEvidenceCLI {
    private struct SnapshotPayload: Codable, Equatable, Sendable {
        var scenario: String
        var outputPath: String
        var width: Double
        var height: Double
        var scale: Double
    }

    private struct PreparedSidecarPayload: Codable, Equatable, Sendable {
        var id: String
        var title: String
        var sidecarPath: String
        var clipPathCandidates: [String]
        var action: String
    }

    private struct PrepareLiveCapturePayload: Codable, Equatable, Sendable {
        var directory: String
        var includeSatisfied: Bool
        var overwrite: Bool
        var writtenCount: Int
        var overwrittenCount: Int
        var skippedExistingCount: Int
        var sidecars: [PreparedSidecarPayload]
    }

    private struct CompleteSidecarPayload: Codable, Equatable, Sendable {
        var directory: String
        var id: String
        var title: String
        var sidecarPath: String
        var clipPath: String
        var clipExists: Bool
        var clipMeetsMinimumByteCount: Bool
        var clipHasSupportedContainer: Bool
        var action: String
        var sidecarCompleteAfterWrite: Bool
        var incompleteSidecarLabels: [String]
        var targetSatisfiedAfterWrite: Bool
    }

    static func run(_ arguments: [String], wantsJSON: Bool) throws -> Int {
        guard let subcommand = arguments.first, !subcommand.hasPrefix("--") else {
            throw WorkflowCLIError(
                "unsupportedCommand",
                "Expected a workflow product-evidence command: snapshot, audit, capture-plan, prepare-live-capture, complete-sidecar, or sidecar-template."
            )
        }
        let remaining = Array(arguments.dropFirst())
        let command = "workflow product-evidence \(subcommand)"

        switch subcommand {
        case "snapshot":
            return try runSnapshot(remaining, command: command, wantsJSON: wantsJSON)
        case "audit":
            return try runAudit(remaining, command: command, wantsJSON: wantsJSON)
        case "capture-plan":
            return try runCapturePlan(remaining, command: command, wantsJSON: wantsJSON)
        case "prepare-live-capture":
            return try runPrepareLiveCapture(remaining, command: command, wantsJSON: wantsJSON)
        case "complete-sidecar":
            return try runCompleteSidecar(remaining, command: command, wantsJSON: wantsJSON)
        case "sidecar-template":
            return try runSidecarTemplate(remaining, command: command, wantsJSON: wantsJSON)
        default:
            throw WorkflowCLIError(
                "unsupportedCommand",
                "Unsupported workflow product-evidence command '\(subcommand)'.",
                path: subcommand
            )
        }
    }

    private static func runSnapshot(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        guard let scenarioArgument = arguments.first,
              !scenarioArgument.hasPrefix("--") else {
            throw WorkflowCLIError(
                "missingArgument",
                "Expected a snapshot scenario: idle, drag-link-authoring, task-reorder-authoring, running, run-center, failed-run-detail, failed-run-preview-unavailable, visual-diagnostics-drill-in, branch-evidence, editor-preview-affordances, template-baseline-preview-refs, or semantic-review-timeline."
            )
        }
        guard let scenario = AutomationProductEvidenceSnapshotScenario(argument: scenarioArgument) else {
            throw WorkflowCLIError(
                "unsupportedScenario",
                "Unsupported product evidence snapshot scenario '\(scenarioArgument)'.",
                path: scenarioArgument
            )
        }

        var outputURL = URL(fileURLWithPath: "docs/workflow-page-productization/product-evidence")
            .appendingPathComponent(scenario.filename, isDirectory: false)
        var width: Double = 1440
        var height: Double = scenario.defaultHeight
        var scale: Double = 2
        var index = 1

        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--json":
                break
            case "--output":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--output requires a file path.", path: token)
                }
                outputURL = URL(fileURLWithPath: arguments[index + 1], isDirectory: false)
                index += 1
            case "--width":
                width = try positiveDoubleOption(arguments, index: index, option: token)
                index += 1
            case "--height":
                height = try positiveDoubleOption(arguments, index: index, option: token)
                index += 1
            case "--scale":
                scale = try positiveDoubleOption(arguments, index: index, option: token)
                index += 1
            default:
                try rejectUnexpected(token)
            }
            index += 1
        }

        let resolvedOutputURL = outputURL.standardizedFileURL
        try MainActor.assumeIsolated {
            try AutomationProductEvidenceSnapshotRenderer.render(
                scenario: scenario,
                outputURL: resolvedOutputURL,
                width: CGFloat(width),
                height: CGFloat(height),
                scale: CGFloat(scale)
            )
        }

        let payload = SnapshotPayload(
            scenario: scenario.rawValue,
            outputPath: resolvedOutputURL.path,
            width: width,
            height: height,
            scale: scale
        )
        let envelope = AutomationCLIResultEnvelope<SnapshotPayload>(
            ok: true,
            command: command,
            data: payload
        )
        if wantsJSON {
            writeJSON(envelope)
        } else {
            write("SparkleRecorder: wrote \(scenario.rawValue) product evidence snapshot -> \(resolvedOutputURL.path)\n")
        }
        return 0
    }

    private static func runAudit(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        var directoryURL = defaultDirectoryURL()
        var requireLive = false
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--json":
                break
            case "--require-live":
                requireLive = true
            case "--directory":
                directoryURL = URL(fileURLWithPath: try value(after: token, in: arguments, at: &index), isDirectory: true)
            default:
                try rejectUnexpected(token)
            }
            index += 1
        }

        let resolvedDirectoryURL = directoryURL.standardizedFileURL
        let snapshot = try WorkflowProductEvidenceDirectory.snapshot(at: resolvedDirectoryURL)
        let payload = AutomationProductEvidenceAudit.evaluate(
            directory: resolvedDirectoryURL.path,
            existingPaths: snapshot.existingPaths,
            sidecarContents: snapshot.sidecarContents,
            fileByteCounts: snapshot.fileByteCounts,
            clipContainers: snapshot.clipContainers
        )
        let missingMessages = payload.items
            .filter { $0.required && !$0.satisfied }
            .map { item in
                AutomationCLIMessage(
                    code: "missingProductEvidence",
                    message: "\(item.title) is not yet backed by the expected product-evidence files and sidecar content.",
                    path: item.id
                )
            }
        let nextActions = [
            AutomationCLINextAction(
                command: "Record missing live artifacts and add same-name .md sidecars under docs/workflow-page-productization/product-evidence/",
                reason: "S0 live-product checklist items stay unchecked until real App evidence exists."
            ),
            AutomationCLINextAction(
                command: "SparkleRecorder workflow product-evidence audit --require-live --json",
                reason: "Use the strict audit gate before claiming S0 Workflow Evidence Closure."
            )
        ]
        let envelope = AutomationCLIResultEnvelope<AutomationProductEvidenceAuditPayload>(
            ok: !requireLive || payload.allRequiredPresent,
            command: command,
            data: payload,
            warnings: requireLive ? [] : missingMessages,
            errors: requireLive ? missingMessages : [],
            nextActions: payload.allRequiredPresent ? [] : nextActions
        )

        if wantsJSON {
            writeJSON(envelope)
        } else {
            write("SparkleRecorder: product evidence audit \(payload.satisfiedRequiredCount)/\(payload.requiredCount) required items present.\n")
            if !payload.missingRequiredIDs.isEmpty {
                write("Missing required evidence: \(payload.missingRequiredIDs.joined(separator: ", "))\n")
            }
        }
        return requireLive && !payload.allRequiredPresent ? 1 : 0
    }

    private static func runCapturePlan(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        var directoryURL = defaultDirectoryURL()
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--json":
                break
            case "--directory":
                directoryURL = URL(fileURLWithPath: try value(after: token, in: arguments, at: &index), isDirectory: true)
            default:
                try rejectUnexpected(token)
            }
            index += 1
        }

        let resolvedDirectoryURL = directoryURL.standardizedFileURL
        let snapshot = try WorkflowProductEvidenceDirectory.snapshot(at: resolvedDirectoryURL)
        let payload = AutomationProductEvidenceAudit.liveCapturePlan(
            directory: resolvedDirectoryURL.path,
            existingPaths: snapshot.existingPaths,
            sidecarContents: snapshot.sidecarContents,
            fileByteCounts: snapshot.fileByteCounts,
            clipContainers: snapshot.clipContainers
        )
        let warnings = payload.items
            .filter { !$0.satisfied }
            .map { item in
                AutomationCLIMessage(
                    code: "missingLiveProductEvidence",
                    message: "\(item.title) still needs a live clip and completed sidecar.",
                    path: item.id
                )
            }
        let envelope = AutomationCLIResultEnvelope<AutomationProductEvidenceCapturePlanPayload>(
            ok: true,
            command: command,
            data: payload,
            warnings: warnings,
            nextActions: payload.allLiveSatisfied ? [
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow product-evidence audit --require-live --json",
                    reason: "Run the strict gate before marking S0 complete."
                )
            ] : [
                AutomationCLINextAction(
                    command: "Use sidecarTemplateCommand before recording, then sidecarCompletionCommand after saving the live clip.",
                    reason: "The plan keeps preparation, reviewed metadata entry and strict completion separate."
                ),
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow product-evidence audit --require-live --json",
                    reason: "Strict S0 audit must remain red until every live clip and sidecar is present."
                )
            ]
        )

        if wantsJSON {
            writeJSON(envelope)
        } else {
            write("SparkleRecorder: S0 live capture plan \(payload.missingLiveCount)/\(payload.items.count) live gates missing.\n")
            for item in payload.items {
                let status = item.satisfied ? "satisfied" : "missing"
                write("\n- \(item.title) [\(status)]\n")
                write("  \(item.note)\n")
                for option in item.options {
                    write("  option sidecar: \(option.sidecarPath)\n")
                    write("    clips: \(option.clipPathCandidates.joined(separator: ", "))\n")
                    write("    template: \(option.sidecarTemplateCommand)\n")
                    write("    complete: \(option.sidecarCompletionCommand)\n")
                    if !option.missingPaths.isEmpty { write("    missing: \(option.missingPaths.joined(separator: ", "))\n") }
                    if !option.undersizedPaths.isEmpty { write("    undersized: \(option.undersizedPaths.joined(separator: ", "))\n") }
                    if !option.invalidClipContainerPaths.isEmpty { write("    invalid clip container: \(option.invalidClipContainerPaths.joined(separator: ", "))\n") }
                    if !option.incompleteSidecarLabels.isEmpty { write("    incomplete labels: \(option.incompleteSidecarLabels.joined(separator: ", "))\n") }
                }
            }
        }
        return 0
    }

    private static func runPrepareLiveCapture(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        var directoryURL = defaultDirectoryURL()
        var includeSatisfied = false
        var overwrite = false
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--json":
                break
            case "--include-satisfied":
                includeSatisfied = true
            case "--overwrite":
                overwrite = true
            case "--directory":
                directoryURL = URL(fileURLWithPath: try value(after: token, in: arguments, at: &index), isDirectory: true)
            default:
                try rejectUnexpected(token)
            }
            index += 1
        }

        let resolvedDirectoryURL = directoryURL.standardizedFileURL
        try FileManager.default.createDirectory(at: resolvedDirectoryURL, withIntermediateDirectories: true)
        let snapshot = try WorkflowProductEvidenceDirectory.snapshot(at: resolvedDirectoryURL)
        let draftsPayload = AutomationProductEvidenceAudit.liveSidecarDrafts(
            directory: resolvedDirectoryURL.path,
            existingPaths: snapshot.existingPaths,
            sidecarContents: snapshot.sidecarContents,
            fileByteCounts: snapshot.fileByteCounts,
            clipContainers: snapshot.clipContainers,
            includeSatisfied: includeSatisfied
        )

        var writtenCount = 0
        var overwrittenCount = 0
        var skippedExistingCount = 0
        var sidecars: [PreparedSidecarPayload] = []
        for draft in draftsPayload.drafts {
            let sidecarURL = resolvedDirectoryURL.appendingPathComponent(draft.sidecarPath, isDirectory: false)
            let exists = FileManager.default.fileExists(atPath: sidecarURL.path)
            let action: String
            if exists && !overwrite {
                skippedExistingCount += 1
                action = "skippedExisting"
            } else {
                try draft.template.write(to: sidecarURL, atomically: true, encoding: .utf8)
                if exists {
                    overwrittenCount += 1
                    action = "overwritten"
                } else {
                    writtenCount += 1
                    action = "written"
                }
            }
            sidecars.append(PreparedSidecarPayload(
                id: draft.id,
                title: draft.title,
                sidecarPath: draft.sidecarPath,
                clipPathCandidates: draft.clipPathCandidates,
                action: action
            ))
        }

        let payload = PrepareLiveCapturePayload(
            directory: resolvedDirectoryURL.path,
            includeSatisfied: includeSatisfied,
            overwrite: overwrite,
            writtenCount: writtenCount,
            overwrittenCount: overwrittenCount,
            skippedExistingCount: skippedExistingCount,
            sidecars: sidecars
        )
        let envelope = AutomationCLIResultEnvelope<PrepareLiveCapturePayload>(
            ok: true,
            command: command,
            data: payload,
            warnings: skippedExistingCount == 0 ? [] : [
                AutomationCLIMessage(
                    code: "existingSidecarSkipped",
                    message: "\(skippedExistingCount) sidecar draft(s) already existed and were left untouched.",
                    path: resolvedDirectoryURL.path
                )
            ],
            nextActions: [
                AutomationCLINextAction(
                    command: "Fill every sidecar placeholder, save the matching live .mov or .mp4 clip, then rerun capture-plan.",
                    reason: "Prepared sidecars intentionally remain incomplete until a real App recording is reviewed."
                ),
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow product-evidence audit --require-live --json",
                    reason: "Strict S0 audit must stay red until clips and completed sidecars exist."
                )
            ]
        )

        if wantsJSON {
            writeJSON(envelope)
        } else {
            write("SparkleRecorder: prepared \(writtenCount) S0 live sidecar draft(s), overwrote \(overwrittenCount), skipped \(skippedExistingCount).\n")
            for sidecar in sidecars {
                write("- \(sidecar.sidecarPath) [\(sidecar.action)] clips: \(sidecar.clipPathCandidates.joined(separator: ", "))\n")
            }
            if sidecars.isEmpty {
                write("No sidecar drafts were needed for the selected capture set.\n")
            }
        }
        return 0
    }

    private static func runCompleteSidecar(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        guard let id = arguments.first, !id.hasPrefix("--") else {
            throw WorkflowCLIError(
                "missingArgument",
                "Expected a live product evidence id, such as 'live-visual-diagnostics-open-reveal'."
            )
        }

        var directoryURL = defaultDirectoryURL()
        var sidecarPath: String?
        var clipPath: String?
        var captureDate: String?
        var worktreeNote: String?
        var appBuildRunSource: String?
        var workflowPackage: String?
        var userAction: String?
        var knownGaps: String?
        var evidenceSource: String?
        var overwrite = false
        var index = 1

        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--json":
                break
            case "--overwrite":
                overwrite = true
            case "--directory":
                directoryURL = URL(fileURLWithPath: try value(after: token, in: arguments, at: &index), isDirectory: true)
            case "--sidecar":
                sidecarPath = try value(after: token, in: arguments, at: &index)
            case "--clip":
                clipPath = try value(after: token, in: arguments, at: &index)
            case "--capture-date":
                captureDate = try value(after: token, in: arguments, at: &index)
            case "--worktree-note":
                worktreeNote = try value(after: token, in: arguments, at: &index)
            case "--app-build":
                appBuildRunSource = try value(after: token, in: arguments, at: &index)
            case "--workflow":
                workflowPackage = try value(after: token, in: arguments, at: &index)
            case "--user-action":
                userAction = try value(after: token, in: arguments, at: &index)
            case "--known-gaps":
                knownGaps = try value(after: token, in: arguments, at: &index)
            case "--evidence-source":
                evidenceSource = try value(after: token, in: arguments, at: &index)
            default:
                try rejectUnexpected(token)
            }
            index += 1
        }

        let completion = AutomationProductEvidenceSidecarCompletion(
            clipPath: try requiredCompletionValue(clipPath, option: "--clip"),
            captureDate: try requiredCompletionValue(captureDate, option: "--capture-date"),
            worktreeNote: try requiredCompletionValue(worktreeNote, option: "--worktree-note"),
            appBuildRunSource: try requiredCompletionValue(appBuildRunSource, option: "--app-build"),
            workflowPackage: try requiredCompletionValue(workflowPackage, option: "--workflow"),
            userAction: try requiredCompletionValue(userAction, option: "--user-action"),
            knownGaps: try requiredCompletionValue(knownGaps, option: "--known-gaps"),
            evidenceSource: try requiredCompletionValue(evidenceSource, option: "--evidence-source")
        )
        guard let completed = AutomationProductEvidenceAudit.completedLiveSidecar(
            id: id,
            sidecarPath: sidecarPath,
            completion: completion
        ) else {
            throw WorkflowCLIError(
                "unsupportedProductEvidence",
                "No live sidecar completion is defined for '\(id)' with clip '\(completion.clipPath)'. Use capture-plan for accepted filenames.",
                path: id
            )
        }

        let resolvedDirectoryURL = directoryURL.standardizedFileURL
        try FileManager.default.createDirectory(at: resolvedDirectoryURL, withIntermediateDirectories: true)
        let existingSnapshot = try WorkflowProductEvidenceDirectory.snapshot(at: resolvedDirectoryURL)
        let existingPlan = AutomationProductEvidenceAudit.liveCapturePlan(
            directory: resolvedDirectoryURL.path,
            existingPaths: existingSnapshot.existingPaths,
            sidecarContents: existingSnapshot.sidecarContents,
            fileByteCounts: existingSnapshot.fileByteCounts,
            clipContainers: existingSnapshot.clipContainers
        )
        let existingOption = existingPlan.items
            .first { $0.id == completed.id }?
            .options
            .first { $0.sidecarPath == completed.sidecarPath }
        if existingSnapshot.existingPaths.contains(completed.sidecarPath),
           existingOption?.incompleteSidecarLabels.isEmpty == true,
           !overwrite {
            throw WorkflowCLIError(
                "sidecarAlreadyComplete",
                "\(completed.sidecarPath) already has all required labels. Pass --overwrite to replace it.",
                path: completed.sidecarPath
            )
        }

        let sidecarURL = resolvedDirectoryURL.appendingPathComponent(completed.sidecarPath, isDirectory: false)
        let existedBeforeWrite = FileManager.default.fileExists(atPath: sidecarURL.path)
        try completed.content.write(to: sidecarURL, atomically: true, encoding: .utf8)

        let refreshedSnapshot = try WorkflowProductEvidenceDirectory.snapshot(at: resolvedDirectoryURL)
        let refreshedPlan = AutomationProductEvidenceAudit.liveCapturePlan(
            directory: resolvedDirectoryURL.path,
            existingPaths: refreshedSnapshot.existingPaths,
            sidecarContents: refreshedSnapshot.sidecarContents,
            fileByteCounts: refreshedSnapshot.fileByteCounts,
            clipContainers: refreshedSnapshot.clipContainers
        )
        let refreshedItem = refreshedPlan.items.first { $0.id == completed.id }
        let refreshedOption = refreshedItem?.options.first { $0.sidecarPath == completed.sidecarPath }
        let incompleteSidecarLabels = refreshedOption?.incompleteSidecarLabels ?? []
        let clipExists = refreshedSnapshot.existingPaths.contains(completed.clipPath)
        let clipMeetsMinimumByteCount = clipExists &&
            (refreshedSnapshot.fileByteCounts[completed.clipPath] ?? 0) >= AutomationProductEvidenceAudit.minimumLiveClipByteCount
        let clipHasSupportedContainer = refreshedSnapshot.clipContainers[completed.clipPath]?.isSupported == true
        let action = existedBeforeWrite ? (overwrite ? "overwritten" : "completedDraft") : "written"
        let payload = CompleteSidecarPayload(
            directory: resolvedDirectoryURL.path,
            id: completed.id,
            title: completed.title,
            sidecarPath: completed.sidecarPath,
            clipPath: completed.clipPath,
            clipExists: clipExists,
            clipMeetsMinimumByteCount: clipMeetsMinimumByteCount,
            clipHasSupportedContainer: clipHasSupportedContainer,
            action: action,
            sidecarCompleteAfterWrite: incompleteSidecarLabels.isEmpty,
            incompleteSidecarLabels: incompleteSidecarLabels,
            targetSatisfiedAfterWrite: refreshedItem?.satisfied == true
        )

        let warning: AutomationCLIMessage?
        if !payload.sidecarCompleteAfterWrite {
            warning = AutomationCLIMessage(
                code: "incompleteLiveSidecar",
                message: "\(completed.sidecarPath) still has incomplete or invalid live capture labels: \(payload.incompleteSidecarLabels.joined(separator: ", ")).",
                path: completed.sidecarPath
            )
        } else if !clipExists {
            warning = AutomationCLIMessage(
                code: "missingLiveClip",
                message: "\(completed.clipPath) is not present yet; the sidecar is complete but the live gate remains open.",
                path: completed.clipPath
            )
        } else if !clipMeetsMinimumByteCount {
            warning = AutomationCLIMessage(
                code: "undersizedLiveClip",
                message: "\(completed.clipPath) is present but empty or size-unknown; replace it with the real live recording.",
                path: completed.clipPath
            )
        } else if !clipHasSupportedContainer {
            warning = AutomationCLIMessage(
                code: "invalidLiveClipContainer",
                message: "\(completed.clipPath) is present but does not look like a supported .mov/.mp4 video container.",
                path: completed.clipPath
            )
        } else {
            warning = nil
        }

        let nextActions: [AutomationCLINextAction]
        if payload.targetSatisfiedAfterWrite {
            nextActions = [AutomationCLINextAction(
                command: "SparkleRecorder workflow product-evidence audit --require-live --json",
                reason: "This item now has a matching clip and completed sidecar; rerun the strict gate."
            )]
        } else if !payload.sidecarCompleteAfterWrite {
            nextActions = [
                AutomationCLINextAction(
                    command: "Review \(completed.sidecarPath), fix invalid labels, then rerun capture-plan.",
                    reason: "S0 live sidecars must name one accepted clip, include worktree context, and identify a live recording source."
                ),
                strictAuditAction
            ]
        } else {
            nextActions = [
                AutomationCLINextAction(
                    command: "Save or replace the live clip as \(completed.clipPath), then rerun capture-plan.",
                    reason: "S0 live evidence requires both the completed sidecar and a non-empty supported .mov/.mp4 recording."
                ),
                strictAuditAction
            ]
        }

        let envelope = AutomationCLIResultEnvelope<CompleteSidecarPayload>(
            ok: true,
            command: command,
            data: payload,
            warnings: warning.map { [$0] } ?? [],
            nextActions: nextActions
        )
        if wantsJSON {
            writeJSON(envelope)
        } else {
            write("""
            SparkleRecorder: completed sidecar \(payload.sidecarPath) [\(payload.action)].
            - clip: \(payload.clipPath) \(payload.clipExists ? "present" : "missing")
            - clip non-empty: \(payload.clipMeetsMinimumByteCount ? "yes" : "no")
            - clip video container: \(payload.clipHasSupportedContainer ? "yes" : "no")
            - sidecar labels complete: \(payload.sidecarCompleteAfterWrite ? "yes" : "no")
            - incomplete labels: \(payload.incompleteSidecarLabels.isEmpty ? "none" : payload.incompleteSidecarLabels.joined(separator: ", "))
            - live gate satisfied: \(payload.targetSatisfiedAfterWrite ? "yes" : "no")

            """)
        }
        return 0
    }

    private static func runSidecarTemplate(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        guard let id = arguments.first, !id.hasPrefix("--") else {
            throw WorkflowCLIError(
                "missingArgument",
                "Expected a live product evidence id, such as 'live-visual-diagnostics-open-reveal'."
            )
        }
        var sidecarPath: String?
        var index = 1
        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--json":
                break
            case "--sidecar":
                sidecarPath = try value(after: token, in: arguments, at: &index)
            default:
                try rejectUnexpected(token)
            }
            index += 1
        }

        guard let payload = AutomationProductEvidenceAudit.liveSidecarTemplate(id: id, sidecarPath: sidecarPath) else {
            throw WorkflowCLIError(
                "unsupportedProductEvidence",
                "No live sidecar template is defined for '\(id)'.",
                path: id
            )
        }
        let envelope = AutomationCLIResultEnvelope<AutomationProductEvidenceSidecarTemplatePayload>(
            ok: true,
            command: command,
            data: payload,
            nextActions: [AutomationCLINextAction(
                command: "Save the filled sidecar next to the live clip, then run workflow product-evidence audit --require-live --json",
                reason: "Strict S0 audit requires the clip and sidecar fields before the gate can close."
            )]
        )
        if wantsJSON {
            writeJSON(envelope)
        } else {
            write(payload.template + "\n")
        }
        return 0
    }

    private static var strictAuditAction: AutomationCLINextAction {
        AutomationCLINextAction(
            command: "SparkleRecorder workflow product-evidence audit --require-live --json",
            reason: "Strict S0 audit must stay red until every live gate is satisfied."
        )
    }

    private static func defaultDirectoryURL() -> URL {
        URL(fileURLWithPath: AutomationProductEvidenceAudit.defaultDirectory, isDirectory: true)
    }

    private static func positiveDoubleOption(
        _ arguments: [String],
        index: Int,
        option: String
    ) throws -> Double {
        guard index + 1 < arguments.count,
              let value = Double(arguments[index + 1]),
              value > 0 else {
            throw WorkflowCLIError("invalidArgument", "\(option) requires a positive number.", path: option)
        }
        return value
    }

    private static func value(
        after option: String,
        in arguments: [String],
        at index: inout Int
    ) throws -> String {
        guard index + 1 < arguments.count else {
            throw WorkflowCLIError("missingArgument", "\(option) requires a value.", path: option)
        }
        index += 1
        return arguments[index]
    }

    private static func requiredCompletionValue(_ value: String?, option: String) throws -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            throw WorkflowCLIError("missingArgument", "\(option) requires a non-empty value.", path: option)
        }
        guard !trimmed.hasPrefix("<"), !trimmed.hasSuffix(">") else {
            throw WorkflowCLIError("placeholderValue", "\(option) must not be an angle-bracket placeholder.", path: option)
        }
        return trimmed
    }

    private static func rejectUnexpected(_ token: String) throws {
        if token.hasPrefix("--") {
            throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
        }
        throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
    }

    private static func writeJSON<Value: Encodable>(_ value: Value) {
        writeWorkflowJSON(value)
    }

    private static func write(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
    }
}
