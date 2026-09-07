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
    var usage: String?

    var summary: String {
        switch command {
        case "help":
            return usage ?? MacroReconstructionCLI.usage
        case "inspect":
            return (["Candidate action IDs (revision: candidate):"] + (actions ?? []).map {
                "\($0.actionID)  \($0.kind)  events \($0.eventIndices)"
            }).joined(separator: "\n")
        case "export":
            return (["Exported reconstruction package: \(outputPath ?? "")", "Next: start with harness.json, follow its staged reading plan, have your AI tool write candidate.json, then import either the package directory or candidate.json."] + (packageReport?.warnings ?? [])).joined(separator: "\n")
        default:
            return "Imported candidate \(candidateID?.uuidString ?? ""). The accepted macro is unchanged.\nNext: open this macro in the library, choose Refine, select this candidate, and Test once before accepting it."
                + (requiresAttention == true ? "\nReview the candidate’s uncertainties; correct them or explicitly acknowledge them before acceptance." : "")
        }
    }
}

/// Authoring-only CLI boundary. This exposes no test receipt, playback, schedule,
/// success or acceptance operation; the app owns those user-driven transitions.
enum MacroReconstructionCLI {
    static let usage = """
    Refine a recorded macro with an external AI tool:
      1. Find your macro: SparkleRecorder workflow macros --json
      2. Export: SparkleRecorder reconstruction export --macro-id <UUID> [--output <new-directory>] [--include-video]
      3. Start with harness.json. Follow its staged reading plan and have your AI tool write candidate.json into the exported package.
      4. Inspect action IDs: SparkleRecorder reconstruction inspect --macro <candidate.json>
      5. Import either the package or candidate file: SparkleRecorder reconstruction import --macro-id <UUID> --candidate <package-directory-or-candidate.json>
      6. In the app library, open Refine, select the imported candidate, Test once, and review the result before accepting.
    --json returns structured results. Export stays local; visual bytes require --include-video.
    Import keeps the accepted macro unchanged. Inspection checks structure; import validates source coverage.
    harness.json is the small entry point; reconstruction.json is the primary action inventory; authoring-contract.json and candidate-template.json are intended for the draft/self-check stage.
    External candidates preserve package Playback Surfaces; every text action explicitly references its intended surface. Live window rebinding stays in the app.
    Testing controls the target app. Restoring a macro does not undo actions in other apps.
    """

    static func parse(_ arguments: [String]) throws -> MacroReconstructionCLIRequest {
        let helpArguments = arguments.filter { $0 != "--json" }
        if arguments.filter({ $0 == "--json" }).count <= 1,
           helpArguments.isEmpty || [["help"], ["--help"], ["-h"], ["inspect", "--help"], ["export", "--help"], ["import", "--help"]].contains(helpArguments) {
            return MacroReconstructionCLIRequest(command: "help")
        }
        guard let command = arguments.first, ["inspect", "export", "import"].contains(command) else {
            throw MacroReconstructionCLIError(code: "unsupportedCommand", message:
                "Expected reconstruction inspect --macro <file>, export --macro-id <UUID> [--output <directory>] [--include-video], or import --macro-id <UUID> --candidate <package-directory-or-candidate.json>.")
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
        if request.command == "help" { return MacroReconstructionCLIResult(command: "help", usage: usage) }
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
            let input = URL(fileURLWithPath: path)
            let source = try await repository.loadMacro(for: macroID)
            let decoded = try MacroReconstructionCandidateInputResolver.decodeInput(
                at: input,
                source: source
            )
            let candidate = try await repository.importCandidate(
                decoded.document,
                for: macroID,
                importProvenance: decoded.importProvenance
            )
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
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["macro"] != nil else {
            throw MacroReconstructionCLIError(
                code: "invalidMacro",
                message: "Expected a candidate document JSON object produced from the reconstruction authoring interface."
            )
        }
        return try MacroReconstructionCandidateInputResolver.decodeCandidate(data).macro
    }
}
