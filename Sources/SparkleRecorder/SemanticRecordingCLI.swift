import Foundation
import SparkleRecorderCore
import SparkleRecorderTooling

enum SemanticRecordingCLI {
    static func run(
        _ arguments: [String],
        wantsJSON: Bool
    ) throws -> Int {
        guard !arguments.isEmpty else {
            throw WorkflowCLIError(
                "unsupportedCommand",
                "Expected a recording command, such as 'recording show checkout-demo --fixture checkout --json'."
            )
        }

        if arguments[0] == "list" {
            return try runList(Array(arguments.dropFirst()), command: "recording.list", wantsJSON: wantsJSON)
        }
        if arguments[0] == "macro-links" {
            return try runMacroLinks(Array(arguments.dropFirst()), command: "recording.macroLinks", wantsJSON: wantsJSON)
        }
        if arguments[0] == "show" {
            return try runShow(Array(arguments.dropFirst()), command: "recording.show", wantsJSON: wantsJSON)
        }
        if arguments[0] == "explain" {
            return try runExplain(Array(arguments.dropFirst()), command: "recording.explain", wantsJSON: wantsJSON)
        }
        if arguments[0] == "readiness" {
            return try runReadiness(Array(arguments.dropFirst()), command: "recording.readiness", wantsJSON: wantsJSON)
        }
        if arguments[0] == "frames" {
            return try runFrames(Array(arguments.dropFirst()), command: "recording.frames", wantsJSON: wantsJSON)
        }
        if arguments.count >= 2, arguments[0] == "frame", arguments[1] == "show" {
            return try runFrameShow(
                Array(arguments.dropFirst(2)),
                command: "recording.frame.show",
                wantsJSON: wantsJSON
            )
        }
        if arguments[0] == "events-near" {
            return try runEventsNear(Array(arguments.dropFirst()), command: "recording.eventsNear", wantsJSON: wantsJSON)
        }
        if arguments.count >= 2, arguments[0] == "ocr", arguments[1] == "search" {
            return try runOCRSearch(
                Array(arguments.dropFirst(2)),
                command: "recording.ocr.search",
                wantsJSON: wantsJSON
            )
        }
        if arguments.count >= 2, arguments[0] == "visual", arguments[1] == "search" {
            return try runVisualSearch(
                Array(arguments.dropFirst(2)),
                command: "recording.visual.search",
                wantsJSON: wantsJSON
            )
        }
        if arguments.count >= 2,
           arguments[0] == "asset",
           (arguments[1] == "extract" || arguments[1] == "baseline") {
            return try runAssetExtract(
                Array(arguments.dropFirst(2)),
                command: arguments[1] == "baseline" ? "recording.asset.baseline" : "recording.asset.extract",
                wantsJSON: wantsJSON,
                defaultKind: arguments[1] == "baseline" ? .baseline : .imageTemplate
            )
        }
        if arguments[0] == "suggest" {
            return try runSuggest(
                Array(arguments.dropFirst()),
                command: commandName(arguments),
                wantsJSON: wantsJSON
            )
        }

        throw WorkflowCLIError(
            "unsupportedCommand",
            "Unsupported recording command '\(arguments.joined(separator: " "))'."
        )
    }

    static func commandName(_ arguments: [String]) -> String {
        guard let command = arguments.first else {
            return "recording"
        }
        switch command {
        case "macro-links":
            return "recording.macroLinks"
        case "show":
            return "recording.show"
        case "explain":
            return "recording.explain"
        case "readiness":
            return "recording.readiness"
        case "frames":
            return "recording.frames"
        case "frame":
            return arguments.dropFirst().first == "show" ? "recording.frame.show" : "recording.frame"
        case "events-near":
            return "recording.eventsNear"
        case "ocr":
            return arguments.dropFirst().first == "search" ? "recording.ocr.search" : "recording.ocr"
        case "visual":
            return arguments.dropFirst().first == "search" ? "recording.visual.search" : "recording.visual"
        case "asset":
            if let subcommand = arguments.dropFirst().first {
                return "recording.asset.\(subcommand)"
            }
            return "recording.asset"
        case "suggest":
            if let category = arguments.dropFirst().first {
                return "recording.suggest.\(category)"
            }
            return "recording.suggest"
        default:
            return "recording.\(command)"
        }
    }

    private static func runShow(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        let recordingBundle = try RecordingCLIBundleLoader.load(arguments)
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLISummaryPayload>
            .semanticRecordingShow(
                command: command,
                requestedRecordingID: recordingBundle.requestedRecordingID,
                bundle: recordingBundle.bundle,
                fixture: recordingBundle.fixture,
                sourceOption: recordingBundle.sourceOption
            )

        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeShowSummary(envelope.data)
        }
        return 0
    }

    private static func runExplain(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        let recordingBundle = try RecordingCLIBundleLoader.load(arguments)
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIExplainPayload>
            .semanticRecordingExplain(
                command: command,
                requestedRecordingID: recordingBundle.requestedRecordingID,
                bundle: recordingBundle.bundle,
                fixture: recordingBundle.fixture,
                sourceOption: recordingBundle.sourceOption
            )

        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeExplainSummary(envelope.data)
        }
        return 0
    }

    private static func runReadiness(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        var requiresOCRReadiness = false
        var requiresWindowOrAXReadiness = false
        let recordingBundle = try RecordingCLIBundleLoader.loadTolerant(arguments) { token, _, _ in
            switch token {
            case "--json":
                return 0
            case "--require-ocr":
                requiresOCRReadiness = true
                return 0
            case "--require-window-or-ax":
                requiresWindowOrAXReadiness = true
                return 0
            default:
                return nil
            }
        }
        let policy = SemanticRecordingBundleReadinessPolicy(
            capturePolicy: recordingBundle.bundle.capturePolicy,
            requiresOCRObservations: requiresOCRReadiness,
            requiresWindowOrAXObservations: requiresWindowOrAXReadiness
        )
        let readiness = SemanticRecordingBundleReadiness.evaluate(recordingBundle.bundle, policy: policy)
        let followUps = SemanticRecordingCLIPresentation.readinessFollowUps(readiness)
        let artifactFiles = SemanticRecordingArtifactFileAuditor.summary(
            bundle: recordingBundle.bundle,
            bundleDirectory: recordingBundle.bundleDirectory
        )
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIReadinessPayload>
            .semanticRecordingReadiness(
                command: command,
                requestedRecordingID: recordingBundle.requestedRecordingID,
                loadResult: recordingBundle.loadResult,
                readiness: readiness,
                fixture: recordingBundle.fixture,
                sourceOption: recordingBundle.sourceOption,
                bundleDirectory: recordingBundle.bundleDirectory?.path,
                followUps: followUps,
                artifactFiles: artifactFiles
            )

        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeReadinessSummary(envelope.data)
        }
        return 0
    }

    private static func runMacroLinks(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        var macrosDirectory: URL?
        var recordingsRoot: URL?
        var includeUnlinked = false
        var requiresOCRReadiness = false
        var requiresWindowOrAXReadiness = false
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--json":
                break
            case "--macros-dir":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--macros-dir requires a directory path.", path: token)
                }
                macrosDirectory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true).standardizedFileURL
                index += 1
            case "--recordings-root":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--recordings-root requires a path.", path: token)
                }
                recordingsRoot = URL(fileURLWithPath: arguments[index + 1], isDirectory: true).standardizedFileURL
                index += 1
            case "--include-unlinked":
                includeUnlinked = true
            case "--require-ocr":
                requiresOCRReadiness = true
            case "--require-window-or-ax":
                requiresWindowOrAXReadiness = true
            default:
                if token.hasPrefix("--") {
                    throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
                }
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            index += 1
        }

        let resolvedMacrosDirectory = macrosDirectory ?? WorkflowMacroCatalog.defaultDirectory
        let resolvedRecordingsRoot = recordingsRoot ?? RecordingBundleStore.defaultRootDirectory
        let store = RecordingBundleStore(rootDirectory: resolvedRecordingsRoot)
        let manifests = try WorkflowMacroCatalog.load(macrosDirectory: macrosDirectory)
        var links: [SemanticRecordingCLIMacroLinkEntry] = []

        for macro in manifests {
            guard let reference = macro.semanticRecording else {
                if includeUnlinked {
                    links.append(SemanticRecordingCLIMacroLinkEntry(macro: macro, status: .unlinked))
                }
                continue
            }

            let bundleDirectory = resolvedRecordingsRoot.appendingPathComponent(
                SemanticRecordingBundleDirectoryIdentity.directoryName(for: reference.recordingID),
                isDirectory: true
            )
            do {
                let loadResult = try waitForWorkflowCLIAsync {
                    try await store.loadBundleTolerant(recordingID: reference.recordingID)
                }
                let policy = SemanticRecordingBundleReadinessPolicy(
                    capturePolicy: loadResult.bundle.capturePolicy,
                    requiresOCRObservations: requiresOCRReadiness,
                    requiresWindowOrAXObservations: requiresWindowOrAXReadiness
                )
                let readiness = SemanticRecordingBundleReadiness.evaluate(loadResult.bundle, policy: policy)
                let artifactFiles = SemanticRecordingArtifactFileAuditor.summary(
                    bundle: loadResult.bundle,
                    bundleDirectory: bundleDirectory
                )
                var issues: [String] = []
                if loadResult.bundle.id != reference.recordingID {
                    issues.append("loadedRecordingIDMismatch")
                }
                if reference.eventCount != macro.eventCount {
                    issues.append("macroEventCountDiffersFromSemanticReference")
                }
                if reference.bundleRelativePath != MacroSemanticRecordingReference.defaultBundleRelativePath(
                    recordingID: reference.recordingID
                ) {
                    issues.append("bundleRelativePathMismatch")
                }
                if reference.manifestRelativePath != MacroSemanticRecordingReference.defaultManifestRelativePath(
                    recordingID: reference.recordingID
                ) {
                    issues.append("manifestRelativePathMismatch")
                }
                if artifactFiles?.hasIssues == true {
                    issues.append("artifactFilesDegraded")
                }
                links.append(
                    SemanticRecordingCLIMacroLinkEntry(
                        macro: macro,
                        bundleDirectory: bundleDirectory.path,
                        loadResult: loadResult,
                        readiness: readiness,
                        artifactFiles: artifactFiles,
                        issues: issues
                    )
                )
            } catch {
                links.append(
                    SemanticRecordingCLIMacroLinkEntry(
                        macro: macro,
                        bundleDirectory: bundleDirectory.path,
                        issues: ["loadFailed: \(error.localizedDescription)"],
                        status: .failedToLoad
                    )
                )
            }
        }

        let payload = SemanticRecordingCLIMacroLinksPayload(
            macrosRoot: resolvedMacrosDirectory.path,
            recordingsRoot: resolvedRecordingsRoot.path,
            totalMacroCount: manifests.count,
            requiresOCRObservations: requiresOCRReadiness,
            requiresWindowOrAXObservations: requiresWindowOrAXReadiness,
            links: links
        )
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIMacroLinksPayload>
            .semanticRecordingMacroLinks(
                command: command,
                payload: payload,
                recordingsRootSourceOption: recordingsRoot.map {
                    RecordingCLIBundleLoader.sourceOption("--recordings-root", url: $0)
                }
            )

        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeMacroLinksSummary(envelope.data)
        }
        return 0
    }

    private static func runList(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        var fixture: String?
        var recordingsRoot: URL?
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--json":
                break
            case "--fixture":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--fixture requires a fixture name.", path: token)
                }
                fixture = arguments[index + 1]
                index += 1
            case "--recordings-root":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--recordings-root requires a path.", path: token)
                }
                recordingsRoot = URL(fileURLWithPath: arguments[index + 1], isDirectory: true).standardizedFileURL
                index += 1
            default:
                if token.hasPrefix("--") {
                    throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
                }
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            index += 1
        }

        switch (fixture, recordingsRoot) {
        case let (fixture?, nil):
            try RecordingCLIBundleLoader.validateFixture(fixture)
            let entry = SemanticRecordingCLICatalogEntry(
                recordingID: SemanticRecordingFixture.recordingID,
                source: .fixture,
                fixture: fixture,
                manifestAvailable: true
            )
            let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIListPayload>
                .semanticRecordingList(command: command, recordings: [entry], fixture: fixture)
            if wantsJSON {
                writeWorkflowJSON(envelope)
            } else {
                writeListSummary(envelope.data)
            }
            return 0

        case let (nil, recordingsRoot?):
            let store = RecordingBundleStore(rootDirectory: recordingsRoot)
            let catalog = try waitForWorkflowCLIAsync { try await store.listBundleCatalog() }
            let entries = catalog.map { entry in
                SemanticRecordingCLICatalogEntry(
                    recordingID: entry.recordingID,
                    source: .storedBundle,
                    modifiedAt: entry.modifiedAt,
                    manifestAvailable: true
                )
            }
            let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIListPayload>
                .semanticRecordingList(
                    command: command,
                    recordings: entries,
                    recordingsRoot: recordingsRoot.path,
                    sourceOption: RecordingCLIBundleLoader.sourceOption("--recordings-root", url: recordingsRoot)
                )
            if wantsJSON {
                writeWorkflowJSON(envelope)
            } else {
                writeListSummary(envelope.data)
            }
            return 0

        case (.some, .some):
            throw WorkflowCLIError(
                "conflictingRecordingSource",
                "Use only one recording source: --fixture or --recordings-root.",
                path: "--recordings-root"
            )

        case (nil, nil):
            let defaultRoot = RecordingBundleStore.defaultRootDirectory
            let store = RecordingBundleStore(rootDirectory: defaultRoot)
            let catalog = try waitForWorkflowCLIAsync { try await store.listBundleCatalog() }
            let entries = catalog.map { entry in
                SemanticRecordingCLICatalogEntry(
                    recordingID: entry.recordingID,
                    source: .storedBundle,
                    modifiedAt: entry.modifiedAt,
                    manifestAvailable: true
                )
            }
            let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIListPayload>
                .semanticRecordingList(command: command, recordings: entries, recordingsRoot: defaultRoot.path)
            if wantsJSON {
                writeWorkflowJSON(envelope)
            } else {
                writeListSummary(envelope.data)
            }
            return 0
        }
    }

    private static func runFrames(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        let recordingBundle = try RecordingCLIBundleLoader.load(arguments)
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIFramesPayload>
            .semanticRecordingFrames(
                command: command,
                requestedRecordingID: recordingBundle.requestedRecordingID,
                bundle: recordingBundle.bundle,
                fixture: recordingBundle.fixture,
                sourceOption: recordingBundle.sourceOption
            )
        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeFramesSummary(envelope.data)
        }
        return 0
    }

    private static func runFrameShow(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        var frameID: UUID?
        let recordingBundle = try RecordingCLIBundleLoader.load(arguments) { token, index, arguments in
            switch token {
            case "--frame":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--frame requires a frame UUID.", path: token)
                }
                frameID = try WorkflowCLIParsing.uuid(arguments[index + 1], path: token)
                return 1
            default:
                return nil
            }
        }
        guard let frameID else {
            throw WorkflowCLIError("missingArgument", "recording frame show requires --frame <uuid>.", path: "--frame")
        }
        guard let frame = recordingBundle.bundle.frames.first(where: { $0.id == frameID }) else {
            throw WorkflowCLIError(
                "unknownFrame",
                "Recording bundle does not contain frame '\(frameID.uuidString)'.",
                path: "--frame"
            )
        }

        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIFramesPayload>
            .semanticRecordingFrameShow(
                command: command,
                requestedRecordingID: recordingBundle.requestedRecordingID,
                bundle: recordingBundle.bundle,
                frame: frame,
                fixture: recordingBundle.fixture,
                sourceOption: recordingBundle.sourceOption
            )
        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeFramesSummary(envelope.data)
        }
        return 0
    }

    private static func runEventsNear(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        var time: TimeInterval?
        var window: TimeInterval = 1.0
        let recordingBundle = try RecordingCLIBundleLoader.load(arguments) { token, index, arguments in
            switch token {
            case "--time":
                guard index + 1 < arguments.count,
                      let parsedTime = TimeInterval(arguments[index + 1]),
                      parsedTime >= 0 else {
                    throw WorkflowCLIError(
                        "invalidArgument",
                        "--time requires a non-negative number of seconds.",
                        path: token
                    )
                }
                time = parsedTime
                return 1
            case "--window":
                guard index + 1 < arguments.count,
                      let parsedWindow = TimeInterval(arguments[index + 1]),
                      parsedWindow >= 0 else {
                    throw WorkflowCLIError(
                        "invalidArgument",
                        "--window requires a non-negative number of seconds.",
                        path: token
                    )
                }
                window = parsedWindow
                return 1
            default:
                return nil
            }
        }
        guard let time else {
            throw WorkflowCLIError("missingArgument", "recording events-near requires --time <seconds>.", path: "--time")
        }

        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIEventsNearPayload>
            .semanticRecordingEventsNear(
                command: command,
                requestedRecordingID: recordingBundle.requestedRecordingID,
                bundle: recordingBundle.bundle,
                fixture: recordingBundle.fixture,
                sourceOption: recordingBundle.sourceOption,
                time: time,
                window: window
            )
        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeEventsNearSummary(envelope.data)
        }
        return 0
    }

    private static func runOCRSearch(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        var text: String?
        var matchMode: TextMatchMode = .contains
        let recordingBundle = try RecordingCLIBundleLoader.load(arguments) { token, index, arguments in
            switch token {
            case "--text":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--text requires search text.", path: token)
                }
                text = arguments[index + 1]
                return 1
            case "--match":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--match requires contains or exact.", path: token)
                }
                matchMode = try WorkflowCLIParsing.textMatchMode(arguments[index + 1], path: token)
                return 1
            default:
                return nil
            }
        }
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedText.isEmpty else {
            throw WorkflowCLIError("missingArgument", "recording ocr search requires --text <text>.", path: "--text")
        }

        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIOCRSearchPayload>
            .semanticRecordingOCRSearch(
                command: command,
                requestedRecordingID: recordingBundle.requestedRecordingID,
                bundle: recordingBundle.bundle,
                fixture: recordingBundle.fixture,
                sourceOption: recordingBundle.sourceOption,
                text: trimmedText,
                matchMode: matchMode,
                queryResults: queryResults(for: recordingBundle)
            )
        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeOCRSearchSummary(envelope.data)
        }
        return 0
    }

    private static func runVisualSearch(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        var text: String?
        var matchMode: TextMatchMode = .contains
        var kind: RecordingVisualObservationKind?
        var label: String?
        let recordingBundle = try RecordingCLIBundleLoader.load(arguments) { token, index, arguments in
            switch token {
            case "--text":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--text requires search text.", path: token)
                }
                text = arguments[index + 1]
                return 1
            case "--match":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--match requires contains or exact.", path: token)
                }
                matchMode = try WorkflowCLIParsing.textMatchMode(arguments[index + 1], path: token)
                return 1
            case "--kind":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--kind requires a visual observation kind.", path: token)
                }
                kind = try parseVisualObservationKind(arguments[index + 1], path: token)
                return 1
            case "--label":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--label requires a label.", path: token)
                }
                label = arguments[index + 1]
                return 1
            default:
                return nil
            }
        }

        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIVisualSearchPayload>
            .semanticRecordingVisualSearch(
                command: command,
                requestedRecordingID: recordingBundle.requestedRecordingID,
                bundle: recordingBundle.bundle,
                fixture: recordingBundle.fixture,
                sourceOption: recordingBundle.sourceOption,
                text: text,
                matchMode: matchMode,
                kind: kind,
                label: label
            )
        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeVisualSearchSummary(envelope.data)
        }
        return 0
    }

    private static func runAssetExtract(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool,
        defaultKind: SemanticRecordingCLIAssetExtractionKind
    ) throws -> Int {
        var frameID: UUID?
        var region: RecordingBounds?
        var regionSpace: RecordingCoordinateSpace = .framePixels
        var kind = defaultKind
        var name: String?
        var outputRoot: URL?
        var sourceRoot: URL?

        let recordingBundle = try RecordingCLIBundleLoader.load(arguments) { token, index, arguments in
            switch token {
            case "--frame":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--frame requires a frame UUID.", path: token)
                }
                frameID = try WorkflowCLIParsing.uuid(arguments[index + 1], path: token)
                return 1
            case "--region":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--region requires x,y,width,height.", path: token)
                }
                region = try parseRegion(arguments[index + 1], coordinateSpace: regionSpace, path: token)
                return 1
            case "--region-space":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--region-space requires a coordinate space.", path: token)
                }
                regionSpace = try parseRegionSpace(arguments[index + 1], path: token)
                if let existingRegion = region {
                    region = RecordingBounds(rect: existingRegion.rect, coordinateSpace: regionSpace)
                }
                return 1
            case "--kind":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--kind requires imageTemplate, image, or baseline.", path: token)
                }
                kind = try parseAssetExtractionKind(arguments[index + 1], path: token)
                return 1
            case "--name":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--name requires an asset name.", path: token)
                }
                name = arguments[index + 1]
                return 1
            case "--output-root", "--assets-root":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "\(token) requires a directory path.", path: token)
                }
                outputRoot = URL(fileURLWithPath: arguments[index + 1], isDirectory: true).standardizedFileURL
                return 1
            case "--source-root", "--artifact-root":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "\(token) requires a directory path.", path: token)
                }
                sourceRoot = URL(fileURLWithPath: arguments[index + 1], isDirectory: true).standardizedFileURL
                return 1
            default:
                return nil
            }
        }

        guard let frameID else {
            throw WorkflowCLIError("missingArgument", "recording asset extract requires --frame <uuid>.", path: "--frame")
        }
        guard let region else {
            throw WorkflowCLIError(
                "missingArgument",
                "recording asset extract requires --region x,y,width,height.",
                path: "--region"
            )
        }
        guard let name else {
            throw WorkflowCLIError("missingArgument", "recording asset extract requires --name <asset-name>.", path: "--name")
        }
        guard let outputRoot else {
            throw WorkflowCLIError(
                "missingArgument",
                "recording asset extract requires --output-root <draft-package-dir>.",
                path: "--output-root"
            )
        }

        let extraction = try RecordingCLIAssetExtractor.extract(
            bundle: recordingBundle.bundle,
            bundleDirectory: recordingBundle.bundleDirectory,
            sourceRoot: sourceRoot,
            frameID: frameID,
            region: region,
            kind: kind,
            name: name,
            outputRoot: outputRoot
        )
        let query = SemanticRecordingCLIAssetExtractionQuery(
            frameID: frameID,
            region: region,
            kind: kind,
            name: extraction.name,
            assetKey: extraction.materializedAsset.key
        )
        let payload = SemanticRecordingCLIAssetExtractionPayload(
            requestedRecordingID: recordingBundle.requestedRecordingID,
            recordingID: recordingBundle.bundle.id,
            fixture: recordingBundle.fixture,
            query: query,
            sourceArtifactRef: extraction.sourceArtifactRef,
            outputRoot: outputRoot.path,
            materializedAsset: extraction.materializedAsset,
            visualAsset: extraction.visualAsset,
            evidence: extraction.evidence
        )
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLIAssetExtractionPayload>
            .semanticRecordingAssetExtraction(command: command, payload: payload)

        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeAssetExtractionSummary(envelope.data)
        }
        return 0
    }

    private static func runSuggest(
        _ arguments: [String],
        command: String,
        wantsJSON: Bool
    ) throws -> Int {
        guard let categoryToken = arguments.first,
              !categoryToken.hasPrefix("--") else {
            throw WorkflowCLIError(
                "missingArgument",
                "recording suggest requires a category: waits, locators, conditions, cleanup, or all."
            )
        }
        guard let category = SemanticRecordingCLISuggestionCategory(rawValue: categoryToken) else {
            throw WorkflowCLIError(
                "unsupportedSuggestionCategory",
                "Unsupported suggestion category '\(categoryToken)'. Use waits, locators, conditions, cleanup, or all.",
                path: categoryToken
            )
        }

        let recordingBundle = try RecordingCLIBundleLoader.load(Array(arguments.dropFirst()))
        let suggestionResult = suggestionResult(for: recordingBundle, category: category)
        let artifactFiles = SemanticRecordingArtifactFileAuditor.summary(
            bundle: recordingBundle.bundle,
            bundleDirectory: recordingBundle.bundleDirectory
        )
        let envelope = AutomationCLIResultEnvelope<SemanticRecordingCLISuggestionsPayload>
            .semanticRecordingSuggestions(
                command: command,
                requestedRecordingID: recordingBundle.requestedRecordingID,
                bundle: recordingBundle.bundle,
                fixture: recordingBundle.fixture,
                sourceOption: recordingBundle.sourceOption,
                category: category,
                suggestionResult: suggestionResult,
                artifactFiles: artifactFiles
            )

        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeSuggestionsSummary(envelope.data)
        }
        return 0
    }

    private static func queryResults(for loadedBundle: RecordingCLIBundle) -> [RecordingQueryResult] {
        SemanticRecordingQueryEngine.deterministicQueryResults(
            for: loadedBundle.bundle,
            fixture: loadedBundle.fixture
        )
    }

    private static func suggestionResult(
        for loadedBundle: RecordingCLIBundle,
        category: SemanticRecordingCLISuggestionCategory
    ) -> SemanticRecordingSuggestionResult {
        SemanticRecordingQueryEngine.deterministicSuggestions(
            for: loadedBundle.bundle,
            fixture: loadedBundle.fixture,
            query: .kinds(category.suggestionKinds)
        )
    }

    private static func parseVisualObservationKind(
        _ value: String,
        path: String
    ) throws -> RecordingVisualObservationKind {
        guard let kind = RecordingVisualObservationKind(rawValue: value) else {
            throw WorkflowCLIError(
                "unsupportedVisualObservationKind",
                "\(path) must be one of ocrText, axElement, windowSnapshot, pixelSample, imageTemplateCandidate, regionBaseline, regionDiff, or patternCandidate.",
                path: path
            )
        }
        return kind
    }

    private static func parseAssetExtractionKind(
        _ value: String,
        path: String
    ) throws -> SemanticRecordingCLIAssetExtractionKind {
        guard let kind = SemanticRecordingCLIAssetExtractionKind(rawValue: value) else {
            throw WorkflowCLIError(
                "unsupportedAssetKind",
                "\(path) must be imageTemplate, image, or baseline.",
                path: path
            )
        }
        return kind
    }

    private static func parseRegionSpace(
        _ value: String,
        path: String
    ) throws -> RecordingCoordinateSpace {
        guard let space = RecordingCoordinateSpace(rawValue: value) else {
            throw WorkflowCLIError(
                "unsupportedRegionSpace",
                "\(path) must be screenPixels, displayPixels, windowPixels, contentPixels, framePixels, or normalizedFrame.",
                path: path
            )
        }
        return space
    }

    private static func parseRegion(
        _ value: String,
        coordinateSpace: RecordingCoordinateSpace,
        path: String
    ) throws -> RecordingBounds {
        let parts = value
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 4,
              let x = Double(parts[0]),
              let y = Double(parts[1]),
              let width = Double(parts[2]),
              let height = Double(parts[3]),
              width > 0,
              height > 0 else {
            throw WorkflowCLIError(
                "invalidRegion",
                "\(path) must be x,y,width,height with positive width and height.",
                path: path
            )
        }
        return RecordingBounds(
            rect: RecordingRect(x: x, y: y, width: width, height: height),
            coordinateSpace: coordinateSpace
        )
    }

    private static func writeListSummary(_ payload: SemanticRecordingCLIListPayload?) {
        guard let payload else { return }
        var lines = [
            "SparkleRecorder: semantic recordings [\(payload.fixtureMode ? "fixture" : "stored")].",
            "- recordings: \(payload.count)"
        ]
        for recording in payload.recordings {
            let modifiedAt = recording.modifiedAt.map(iso8601String) ?? "unknown"
            lines.append("- \(recording.recordingID.uuidString) source=\(recording.source.rawValue) modifiedAt=\(modifiedAt)")
        }
        writeLines(lines)
    }

    private static func writeShowSummary(_ payload: SemanticRecordingCLISummaryPayload?) {
        guard let payload else { return }
        let target = payload.captureTarget?.appName ?? payload.captureTarget?.appBundleIdentifier ?? "unknown app"
        let surface = payload.captureTarget?.surfaceID ?? "unknown surface"
        FileHandle.standardOutput.write(Data("""
        SparkleRecorder: semantic recording \(payload.requestedRecordingID) [\(payload.fixtureMode ? "fixture" : "live")].
        - recording: \(payload.recordingID.uuidString)
        - target: \(target) / \(surface)
        - video segments: \(payload.videoSegmentCount), frames: \(payload.frameCount), AI-safe events: \(payload.aiSafeEventCount)
        - visual observations: \(payload.visualObservationCount), OCR: \(payload.ocrObservationCount)
        - suppressions: \(payload.suppressionSummary.totalSuppressedCount)

        """.utf8))
    }

    private static func writeReadinessSummary(_ payload: SemanticRecordingCLIReadinessPayload?) {
        guard let payload else { return }
        var lines = [
            "SparkleRecorder: semantic recording readiness \(payload.requestedRecordingID) [\(payload.fixtureMode ? "fixture" : "stored")].",
            "- recording: \(payload.recordingID.uuidString)",
            "- status: \(payload.status.rawValue)",
            "- issues: \(payload.issueCount) (blocking: \(payload.blockingIssueCount), degraded: \(payload.degradedIssueCount))",
            "- loaded sidecars: \(SemanticRecordingCLIPresentation.sidecarKindSummary(payload.load.sidecarDiagnostics.loadedKinds))",
            "- missing sidecars: \(SemanticRecordingCLIPresentation.sidecarKindSummary(payload.load.sidecarDiagnostics.missingKinds))",
            "- failed sidecars: \(SemanticRecordingCLIPresentation.failedSidecarSummary(payload.load.sidecarDiagnostics.failedIssues))"
        ]
        if let artifactFiles = payload.artifactFiles {
            lines.append(
                "- artifact files: \(artifactFiles.presentCount)/\(artifactFiles.checkedCount) present, missing: \(artifactFiles.missingCount), deleted: \(artifactFiles.deletedCount), empty: \(artifactFiles.emptyCount), directory: \(artifactFiles.directoryCount), unsafe: \(artifactFiles.unsafeCount)"
            )
        }
        if let bundleDirectory = payload.bundleDirectory {
            lines.append("- bundle: \(bundleDirectory)")
        }
        for issue in payload.readiness.issues.prefix(6) {
            lines.append("- \(issue.code.rawValue) [\(issue.severity.rawValue)]: \(issue.message)")
        }
        for followUp in payload.followUps {
            lines.append("- follow-up: \(followUp)")
        }
        writeLines(lines)
    }

    private static func writeMacroLinksSummary(_ payload: SemanticRecordingCLIMacroLinksPayload?) {
        guard let payload else { return }
        var lines = [
            "SparkleRecorder: semantic recording macro links.",
            "- macros root: \(payload.macrosRoot ?? "unknown")",
            "- recordings root: \(payload.recordingsRoot)",
            "- macros: \(payload.totalMacroCount), linked: \(payload.linkedMacroCount), returned: \(payload.returnedCount)",
            "- ready: \(payload.readyCount), degraded: \(payload.degradedCount), not ready: \(payload.notReadyCount), failed: \(payload.failedCount), unlinked: \(payload.unlinkedCount)"
        ]
        for link in payload.links.prefix(12) {
            let recordingID = link.recordingID?.uuidString ?? "none"
            lines.append("- \(link.macroID.uuidString) \(link.macroName): \(link.status.rawValue) recording=\(recordingID)")
            if let artifactFiles = link.artifactFiles {
                lines.append("  artifact files: \(artifactFiles.presentCount)/\(artifactFiles.checkedCount) present")
            }
            for issue in link.issues.prefix(3) {
                lines.append("  issue: \(issue)")
            }
        }
        writeLines(lines)
    }

    private static func writeExplainSummary(_ payload: SemanticRecordingCLIExplainPayload?) {
        guard let payload else { return }
        let target = payload.summary.captureTarget?.appName ??
            payload.summary.captureTarget?.appBundleIdentifier ??
            "unknown app"
        var lines = [
            "SparkleRecorder: semantic recording explanation \(payload.requestedRecordingID) [\(payload.fixtureMode ? "fixture" : "stored")].",
            "- recording: \(payload.recordingID.uuidString)",
            "- target: \(target)",
            "- key points: \(payload.keyPointCount), visual evidence: \(payload.visualEvidenceCount)"
        ]
        for point in payload.keyPoints.prefix(5) {
            let risk = point.risk.map { " risk=\($0)" } ?? ""
            lines.append("- \(point.kind.rawValue) t=\(point.recordingTime)s: \(point.title)\(risk)")
        }
        for note in payload.evidenceNotes {
            lines.append("- note: \(note)")
        }
        writeLines(lines)
    }

    private static func writeFramesSummary(_ payload: SemanticRecordingCLIFramesPayload?) {
        guard let payload else { return }
        var lines = [
            "SparkleRecorder: semantic recording frames \(payload.requestedRecordingID) [\(payload.fixtureMode ? "fixture" : "live")].",
            "- frames: \(payload.count)"
        ]
        for frame in payload.frames {
            lines.append(
                "- \(frame.id.uuidString) t=\(frame.recordingTime)s source=\(frame.source.rawValue) ref=\(frame.effectiveImageRef.path)"
            )
        }
        writeLines(lines)
    }

    private static func writeEventsNearSummary(_ payload: SemanticRecordingCLIEventsNearPayload?) {
        guard let payload else { return }
        var lines = [
            "SparkleRecorder: semantic recording events near \(payload.query.time)s +/- \(payload.query.window)s.",
            "- events: \(payload.eventCount), frames: \(payload.frameCount)"
        ]
        for event in payload.events {
            lines.append(
                "- \(event.id.uuidString) t=\(event.recordingTime)s kind=\(event.kind.rawValue) summary=\(event.summary ?? "")"
            )
        }
        for frame in payload.frames {
            lines.append("- frame \(frame.id.uuidString) t=\(frame.recordingTime)s ref=\(frame.effectiveImageRef.path)")
        }
        writeLines(lines)
    }

    private static func writeOCRSearchSummary(_ payload: SemanticRecordingCLIOCRSearchPayload?) {
        guard let payload else { return }
        var lines = [
            "SparkleRecorder: OCR search '\(payload.query.text)' [\(payload.fixtureMode ? "fixture" : "live")].",
            "- matches: \(payload.count)"
        ]
        for result in payload.results {
            let ref = result.artifactRef?.path ?? "no artifact ref"
            lines.append(
                "- \(result.observationID.uuidString) t=\(result.recordingTime)s text=\"\(result.text)\" ref=\(ref)"
            )
        }
        writeLines(lines)
    }

    private static func writeVisualSearchSummary(_ payload: SemanticRecordingCLIVisualSearchPayload?) {
        guard let payload else { return }
        let label = payload.query.label.map { " label='\($0)'" } ?? ""
        let kind = payload.query.kind.map { " kind=\($0.rawValue)" } ?? ""
        let text = payload.query.text.map { " text='\($0)'" } ?? ""
        var lines = [
            "SparkleRecorder: visual search\(kind)\(label)\(text) [\(payload.fixtureMode ? "fixture" : "live")].",
            "- matches: \(payload.count)"
        ]
        for result in payload.results {
            let ref = result.artifactRef?.path ?? "no artifact ref"
            lines.append(
                "- \(result.observationID.uuidString) t=\(result.recordingTime)s kind=\(result.kind.rawValue) ref=\(ref)"
            )
        }
        writeLines(lines)
    }

    private static func writeAssetExtractionSummary(_ payload: SemanticRecordingCLIAssetExtractionPayload?) {
        guard let payload else { return }
        writeLines([
            "SparkleRecorder: extracted \(payload.query.kind.rawValue) asset \(payload.query.assetKey) [\(payload.fixtureMode ? "fixture" : "stored")].",
            "- source: \(payload.sourceArtifactRef.path)",
            "- output: \(payload.materializedAsset.destinationPath)",
            "- sha256: \(payload.materializedAsset.sha256)"
        ])
    }

    private static func writeSuggestionsSummary(_ payload: SemanticRecordingCLISuggestionsPayload?) {
        guard let payload else { return }
        var lines = [
            "SparkleRecorder: recording suggestions \(payload.category.rawValue) [\(payload.fixtureMode ? "fixture" : "live")].",
            "- suggestions: \(payload.count)"
        ]
        if let artifactFiles = payload.artifactFiles {
            lines.append(
                "- artifact files: \(artifactFiles.presentCount)/\(artifactFiles.checkedCount) present, missing: \(artifactFiles.missingCount), deleted: \(artifactFiles.deletedCount), empty: \(artifactFiles.emptyCount), directory: \(artifactFiles.directoryCount), unsafe: \(artifactFiles.unsafeCount)"
            )
        }
        for suggestion in payload.suggestions {
            lines.append(
                "- \(suggestion.id.uuidString) \(suggestion.kind.rawValue) confidence=\(suggestion.confidence): \(suggestion.title)"
            )
        }
        writeLines(lines)
    }

    private static func writeLines(_ lines: [String]) {
        FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
