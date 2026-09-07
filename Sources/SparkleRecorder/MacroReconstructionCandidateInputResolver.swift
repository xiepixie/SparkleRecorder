import Foundation
import SparkleRecorderCore

enum MacroReconstructionCandidateInputError: Error, LocalizedError, Equatable, Sendable {
    case missingCandidateInPackage
    case missingPackageMetadata(String)
    case unsupportedPackageVersion(String?)
    case unsupportedContractVersion(String)
    case unsupportedCapabilityVersion(String)
    case unsupportedAuthoringPolicyVersion(String)
    case unsupportedSourceContextVersion(String)
    case unsupportedActionContextVersion(String)
    case packageContractMismatch(String)
    case packageSourceRevisionMismatch
    case outdatedCandidateFormat(field: String)

    var errorDescription: String? {
        switch self {
        case .missingCandidateInPackage:
            String(
                localized: "Reconstruction package does not contain candidate.json. Ask your AI tool to finish the package, then import it again.",
                table: "EditorUX"
            )
        case .missingPackageMetadata(let file):
            String(
                format: String(localized: "Reconstruction package is missing %@. Export the current macro again before importing.", table: "EditorUX"),
                file
            )
        case .unsupportedPackageVersion(let version):
            String(
                format: String(localized: "This reconstruction package version is no longer supported (%@). Export the current macro again.", table: "EditorUX"),
                version ?? "unknown"
            )
        case .unsupportedContractVersion(let version):
            String(
                format: String(localized: "This reconstruction package uses an unsupported contract manifest (%@). Export the current macro again.", table: "EditorUX"),
                version
            )
        case .unsupportedCapabilityVersion(let version):
            String(
                format: String(localized: "This reconstruction package uses an older candidate capability (%@). Export the current macro again.", table: "EditorUX"),
                version
            )
        case .unsupportedAuthoringPolicyVersion(let version):
            String(
                format: String(localized: "This reconstruction package uses an unsupported authoring policy (%@). Export the current macro again.", table: "EditorUX"),
                version
            )
        case .unsupportedSourceContextVersion(let version):
            String(
                format: String(localized: "This reconstruction package uses an unsupported source-context contract (%@). Export the current macro again.", table: "EditorUX"),
                version
            )
        case .unsupportedActionContextVersion(let version):
            String(
                format: String(localized: "This reconstruction package uses an unsupported action-context contract (%@). Export the current macro again.", table: "EditorUX"),
                version
            )
        case .packageContractMismatch(let field):
            String(
                format: String(localized: "Reconstruction package contract metadata disagrees for %@. Export the current macro again instead of mixing package files.", table: "EditorUX"),
                field
            )
        case .packageSourceRevisionMismatch:
            String(
                localized: "candidate.json does not belong to this reconstruction package. Use the candidate generated from this package or export again.",
                table: "EditorUX"
            )
        case .outdatedCandidateFormat(let field):
            String(
                format: String(
                    localized: "This candidate uses an older reconstruction package format (%@). Export the current macro again and generate a new candidate.",
                    table: "EditorUX"
                ),
                field
            )
        }
    }
}

struct MacroReconstructionCandidateInput: Sendable {
    var document: MacroCandidateDocument
    var importProvenance: MacroCandidateImportProvenance
}

/// User-facing reconstruction input seam. It distinguishes a standalone Candidate
/// from a package directory and delegates package semantics to version-specific
/// decoders instead of growing one cross-version parser indefinitely.
enum MacroReconstructionCandidateInputResolver {
    static let candidateFileName = "candidate.json"

    /// Fields emitted by older full-SavedMacro templates but now owned by the app.
    /// Genuine unknown execution fields must still fail strict decoding.
    private static let legacyAppOwnedMacroFields: Set<String> = [
        "libraryOrder", "loops", "speed", "followWindowOffset",
        "icon", "accent", "tags", "favorite", "hotkey", "notes", "chainTo",
        "semanticRecording", "playableSanitization",
        "playCount", "lastPlayedAt", "totalRunTime",
        "cachedDuration", "cachedEventCount", "cachedWaveformBars"
    ]

    static func resolve(_ input: URL, fileManager: FileManager = .default) throws -> URL {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: input.path, isDirectory: &isDirectory) else {
            return input
        }
        guard isDirectory.boolValue else { return input }

        let candidate = input.appendingPathComponent(candidateFileName, isDirectory: false)
        var candidateIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: candidate.path, isDirectory: &candidateIsDirectory),
              !candidateIsDirectory.boolValue else {
            throw MacroReconstructionCandidateInputError.missingCandidateInPackage
        }
        return candidate
    }

    static func decodeInput(
        at input: URL,
        source: SavedMacro? = nil,
        fileManager: FileManager = .default
    ) throws -> MacroReconstructionCandidateInput {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: input.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            let document = try decodeCandidate(at: input, fileManager: fileManager)
            return MacroReconstructionCandidateInput(document: document, importProvenance: .standalone)
        }

        let candidateURL = try resolve(input, fileManager: fileManager)
        let document = try decodeCandidate(Data(contentsOf: candidateURL, options: .mappedIfSafe))
        let harnessURL = input.appendingPathComponent("harness.json")
        var harnessIsDirectory: ObjCBool = false
        let hasCurrentHarness = fileManager.fileExists(
            atPath: harnessURL.path,
            isDirectory: &harnessIsDirectory
        ) && !harnessIsDirectory.boolValue

        if hasCurrentHarness {
            return try MacroReconstructionV4PackageDecoder.decode(
                packageDirectory: input,
                candidate: document,
                acceptedSource: source,
                fileManager: fileManager
            )
        }
        return try MacroReconstructionLegacyV3PackageDecoder.decode(
            packageDirectory: input,
            candidate: document,
            acceptedSource: source,
            fileManager: fileManager
        )
    }

    static func decodeCandidate(
        at input: URL,
        fileManager: FileManager = .default
    ) throws -> MacroCandidateDocument {
        let candidateURL = try resolve(input, fileManager: fileManager)
        return try decodeCandidate(Data(contentsOf: candidateURL, options: .mappedIfSafe))
    }

    static func decodeCandidate(_ data: Data) throws -> MacroCandidateDocument {
        do {
            return try MacroCandidateValidator.decode(data)
        } catch MacroCandidateValidationError.unknownField(let path) {
            let prefix = "macro."
            guard path.hasPrefix(prefix) else { throw MacroCandidateValidationError.unknownField(path) }
            let field = String(path.dropFirst(prefix.count))
            guard legacyAppOwnedMacroFields.contains(field) else {
                throw MacroCandidateValidationError.unknownField(path)
            }
            throw MacroReconstructionCandidateInputError.outdatedCandidateFormat(field: field)
        }
    }
}
