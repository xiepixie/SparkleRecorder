import Foundation

public struct MacroCandidateEventKindDescriptor: Codable, Equatable, Sendable {
    public var code: Int
    public var name: String
    public var family: String
    public var executableMeaning: String
    public var authoringNotes: [String]

    public init(code: Int, name: String, family: String, executableMeaning: String, authoringNotes: [String] = []) {
        self.code = code
        self.name = name
        self.family = family
        self.executableMeaning = executableMeaning
        self.authoringNotes = authoringNotes
    }
}

public struct MacroReconstructionActionKindDescriptor: Codable, Equatable, Sendable {
    public var name: String
    public var exportedByReconstructor: Bool
    public var candidateRepresentation: String
    public var meaning: String

    public init(name: String, exportedByReconstructor: Bool, candidateRepresentation: String, meaning: String) {
        self.name = name
        self.exportedByReconstructor = exportedByReconstructor
        self.candidateRepresentation = candidateRepresentation
        self.meaning = meaning
    }
}

public struct MacroReconstructionEnumCatalog: Codable, Equatable, Sendable {
    public var coordinateBinding: [String]
    public var coordinateStrategy: [String]
    public var locatorFallbackPolicy: [String]
    public var textMatchMode: [String]
    public var coverageDisposition: [String]
    public var reconstructionObjective: [String]
}

public struct MacroReconstructionAuthoringRule: Codable, Equatable, Sendable {
    public var id: String
    public var scope: String
    public var requirement: String

    public init(id: String, scope: String, requirement: String) {
        self.id = id
        self.scope = scope
        self.requirement = requirement
    }
}

/// Detailed machine-readable authoring contract. Unlike harness.json, this file is
/// intentionally comprehensive and should normally be read only during candidate
/// drafting/self-check. Validator-facing vocabulary is generated from the same Core
/// enums so supported actions cannot silently drift away from the exported contract.
public struct MacroReconstructionAuthoringContract: Codable, Equatable, Sendable {
    public static let currentVersion = MacroReconstructionContractVersions.authoringContract

    public var version: String
    public var capabilities: MacroCandidateCapabilities
    public var policy: MacroReconstructionAuthoringPolicy
    public var executableEventKinds: [MacroCandidateEventKindDescriptor]
    public var reconstructionActionKinds: [MacroReconstructionActionKindDescriptor]
    public var enumValues: MacroReconstructionEnumCatalog
    public var rules: [MacroReconstructionAuthoringRule]

    public init(objective: MacroReconstructionObjective) {
        version = Self.currentVersion
        capabilities = .current
        policy = MacroReconstructionAuthoringPolicy(objective: objective)
        executableEventKinds = Self.eventKindDescriptors
        reconstructionActionKinds = Self.actionKindDescriptors
        enumValues = MacroReconstructionEnumCatalog(
            coordinateBinding: CoordinateBinding.allCases.map(\.rawValue),
            coordinateStrategy: CoordinateStrategy.allCases.map(\.rawValue),
            locatorFallbackPolicy: LocatorFallbackPolicy.allCases.map(\.rawValue),
            textMatchMode: TextMatchMode.allCases.map(\.rawValue),
            coverageDisposition: MacroCandidateDisposition.allCases.map(\.rawValue),
            reconstructionObjective: MacroReconstructionObjective.allCases.map(\.rawValue)
        )
        rules = Self.authoringRules
    }

    /// Accepts the exact current authoring contract plus the two v4 capability
    /// snapshots emitted before and during the required-event metadata rollout.
    /// Other rule/capability edits remain rejected as package tampering or drift.
    public func isImportCompatible(objective: MacroReconstructionObjective) -> Bool {
        let expected = Self(objective: objective)
        if self == expected { return true }
        guard version == expected.version,
              capabilities.isImportCompatibleWithCurrent(),
              policy == expected.policy,
              executableEventKinds == expected.executableEventKinds,
              reconstructionActionKinds == expected.reconstructionActionKinds,
              enumValues == expected.enumValues else {
            return false
        }

        if rules == expected.rules { return true }
        guard capabilities.requiredEventFields == nil else { return false }
        let legacyRules = expected.rules.filter { $0.id != "schema.requiredEventFields" }
        return rules == legacyRules
    }
}
