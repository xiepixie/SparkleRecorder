import Foundation
import SparkleRecorderCore

struct MacroReconstructionCLIError: Error, LocalizedError, Equatable, Sendable {
    var code: String
    var message: String
    var errorDescription: String? { message }
}

struct MacroReconstructionCLIRequest: Equatable, Sendable {
    var command: String
    var macroPath: String?
    var macroID: UUID?
    var candidatePath: String?
    var outputPath: String?
    var includeVideo: Bool = false
}

struct MacroReconstructionCLIAction: Codable, Equatable, Sendable {
    var actionID: String
    var kind: String
    var eventIndices: [Int]
    var startTime: Double
    var endTime: Double
}

struct MacroReconstructionCLIResult: Codable, Equatable, Sendable {
    var command: String
    var macroID: UUID?
    var actionRevision: String?
    var actions: [MacroReconstructionCLIAction]?
    var outputPath: String?
    var packageReport: MacroReconstructionPackageReport?
    var candidateID: UUID?
    var normalizedDigest: String?
    var requiresAttention: Bool?

    var summary: String {
        switch command {
        case "inspect":
            return (["Candidate action IDs (revision: candidate):"] + (actions ?? []).map {
                "\($0.actionID)  \($0.kind)  events \($0.eventIndices)"
            }).joined(separator: "\n")
        case "export":
            return (["Exported reconstruction package: \(outputPath ?? "")"] + (packageReport?.warnings ?? [])).joined(separator: "\n")
        default:
            return "Imported candidate \(candidateID?.uuidString ?? ""). Review and test it in the app before acceptance."
        }
    }
}

/// Authoring-only CLI boundary. This exposes no test receipt, playback, schedule,
/// success or acceptance operation; the app owns those user-driven transitions.
enum MacroReconstructionCLI {
    static func parse(_ arguments: [String]) throws -> MacroReconstructionCLIRequest {
        guard let command = arguments.first, ["inspect", "export", "import"].contains(command) else {
            throw MacroReconstructionCLIError(code: "unsupportedCommand", message:
                "Expected reconstruction inspect --macro <file>, export --macro-id <UUID> [--output <directory>] [--include-video], or import --macro-id <UUID> --candidate <file>.")
        }
        var request = MacroReconstructionCLIRequest(command: command)
        var seen = Set<String>()
        var index = 1
        while index < arguments.count {
            let token = arguments[index]
            guard seen.insert(token).inserted else {
                throw MacroReconstructionCLIError(code: "duplicateOption", message: "Duplicate option '\(token)'.")
            }
            if token == "--json" { index += 1; continue }
            if token == "--include-video", command == "export" {
                request.includeVideo = true; index += 1; continue
            }
            let allowed: Set<String>
            switch command {
            case "inspect": allowed = ["--macro"]
            case "export": allowed = ["--macro-id", "--output"]
            default: allowed = ["--macro-id", "--candidate"]
            }
            // A positional macro file is a convenient inspect-only spelling.
            if command == "inspect", !token.hasPrefix("--"), request.macroPath == nil {
                request.macroPath = token; index += 1; continue
            }
            guard allowed.contains(token) else {
                throw MacroReconstructionCLIError(code: "unsupportedOption", message: "Unsupported option '\(token)' for \(command).")
            }
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--"), !arguments[index + 1].isEmpty else {
                throw MacroReconstructionCLIError(code: "missingArgument", message: "\(token) requires a value.")
            }
            let value = arguments[index + 1]
            switch token {
            case "--macro":
                guard request.macroPath == nil else {
                    throw MacroReconstructionCLIError(code: "duplicateOption", message: "Only one macro file may be inspected.")
                }
                request.macroPath = value
            case "--macro-id":
                guard let id = UUID(uuidString: value) else {
                    throw MacroReconstructionCLIError(code: "invalidIdentifier", message: "--macro-id must be a UUID.")
                }
                request.macroID = id
            case "--output": request.outputPath = value
            case "--candidate": request.candidatePath = value
            default: break
            }
            index += 2
        }
        guard command == "inspect" ? request.macroPath != nil : request.macroID != nil,
              command != "import" || request.candidatePath != nil else {
            throw MacroReconstructionCLIError(code: "missingArgument", message: "Required arguments are missing for reconstruction \(command).")
        }
        return request
    }

    static func execute(_ arguments: [String], appSupportURL: URL? = nil,
                        recordingsRoot: URL? = nil) async throws -> MacroReconstructionCLIResult {
        let request = try parse(arguments)
        if request.command == "inspect", let path = request.macroPath {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let macro = try inspectMacro(data)
            let actions = try MacroActionReconstructor.reconstruct(events: macro.events, sourceRevision: "candidate")
            return MacroReconstructionCLIResult(command: "inspect", macroID: macro.id, actionRevision: "candidate",
                actions: actions.map { .init(actionID: $0.id, kind: $0.kind.rawValue,
                    eventIndices: $0.sourceEventIndices, startTime: $0.startTime, endTime: $0.endTime) })
        }
        guard let macroID = request.macroID else {
            throw MacroReconstructionCLIError(code: "missingArgument", message: "--macro-id is required.")
        }
        let repository = MacroRepository(appSupportURL: appSupportURL)
        if request.command == "import", let path = request.candidatePath {
            let document = try MacroCandidateValidator.decode(Data(contentsOf: URL(fileURLWithPath: path)))
            let candidate = try await repository.importCandidate(document, for: macroID)
            return MacroReconstructionCLIResult(command: "import", macroID: macroID, candidateID: candidate.id,
                normalizedDigest: candidate.normalizedDigest, requiresAttention: candidate.document.requiresAttention)
        }
        let source = try await repository.loadMacro(for: macroID)
        var bundle: SemanticRecordingBundle?
        var bundleDirectory: URL?
        if let reference = source.semanticRecording {
            let root = recordingsRoot ?? appSupportURL.map {
                $0.appendingPathComponent("SparkleRecorder/SemanticRecordings", isDirectory: true)
            } ?? RecordingBundleStore.defaultRootDirectory
            let store = RecordingBundleStore(rootDirectory: root)
            // A linked bundle must load before privacy policy can be evaluated;
            // do not silently export source fields when that evidence is unreadable.
            bundle = try await store.loadBundle(recordingID: reference.recordingID)
            bundleDirectory = await store.bundleDirectory(for: reference.recordingID)
        }
        let output = request.outputPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("reconstruction-\(macroID.uuidString)-\(UUID().uuidString)", isDirectory: true)
        let report = try MacroReconstructionPackage.export(source: source, bundle: bundle,
            bundleDirectory: bundleDirectory, includeVisualEvidence: request.includeVideo, to: output)
        return MacroReconstructionCLIResult(command: "export", macroID: macroID,
            outputPath: output.standardizedFileURL.path, packageReport: report)
    }

    private static func inspectMacro(_ data: Data) throws -> SavedMacro {
        guard data.count <= 100_000_000 else {
            throw MacroReconstructionCLIError(code: "fileTooLarge", message: "Macro file exceeds 100 MB.")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MacroReconstructionCLIError(code: "invalidMacro", message: "Expected a SavedMacro or candidate document JSON object.")
        }
        if object["macro"] != nil { return try MacroCandidateValidator.decode(data).macro }
        // Reuse strict playback-field decoding for a standalone SavedMacro too.
        let wrapped: [String: Any] = ["macro": object, "sourceRevision": "candidate", "summary": "",
                                     "coverage": [], "uncertainActionIDs": [], "model": ""]
        return try MacroCandidateValidator.decode(JSONSerialization.data(withJSONObject: wrapped)).macro
    }
}
