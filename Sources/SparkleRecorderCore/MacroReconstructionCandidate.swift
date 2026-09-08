import Foundation

public enum MacroReconstructionObjective: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case faithful
    case robust
}

/// Machine-readable guidance for external reconstruction authors. This policy
/// never grants capabilities beyond `MacroCandidateCapabilities`; it only chooses
/// how aggressively supported transformations should be preferred.
public struct MacroReconstructionAuthoringPolicy: Codable, Equatable, Sendable {
    public static let currentVersion = MacroReconstructionContractVersions.authoringPolicy
    private enum CodingKeys: String, CodingKey {
        case version
        case objective
        case preferEvidenceBackedTextLocators
        case replaceRecordedGapsWithBoundedWaits
        case addVerificationOnlyFromAlignedEvidence
        case preferWindowOrContentRelativeCoordinates
        case preferContentNormalizedTextGeometry
        case preservePathSensitiveGestures
        case prohibitUnsupportedVisualLocators
    }

    public var version: String
    public var objective: MacroReconstructionObjective
    public var preferEvidenceBackedTextLocators: Bool
    public var replaceRecordedGapsWithBoundedWaits: Bool
    public var addVerificationOnlyFromAlignedEvidence: Bool
    public var preferWindowOrContentRelativeCoordinates: Bool
    public var preferContentNormalizedTextGeometry: Bool
    public var preservePathSensitiveGestures: Bool
    public var prohibitUnsupportedVisualLocators: Bool

    public init(objective: MacroReconstructionObjective) {
        self.version = Self.currentVersion
        self.objective = objective
        switch objective {
        case .faithful:
            self.preferEvidenceBackedTextLocators = false
            self.replaceRecordedGapsWithBoundedWaits = false
            self.addVerificationOnlyFromAlignedEvidence = false
            self.preferWindowOrContentRelativeCoordinates = false
            self.preferContentNormalizedTextGeometry = false
        case .robust:
            self.preferEvidenceBackedTextLocators = true
            self.replaceRecordedGapsWithBoundedWaits = true
            self.addVerificationOnlyFromAlignedEvidence = true
            self.preferWindowOrContentRelativeCoordinates = true
            self.preferContentNormalizedTextGeometry = true
        }
        self.preservePathSensitiveGestures = true
        self.prohibitUnsupportedVisualLocators = true
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        objective = try container.decode(MacroReconstructionObjective.self, forKey: .objective)
        preferEvidenceBackedTextLocators = try container.decode(Bool.self, forKey: .preferEvidenceBackedTextLocators)
        replaceRecordedGapsWithBoundedWaits = try container.decode(Bool.self, forKey: .replaceRecordedGapsWithBoundedWaits)
        addVerificationOnlyFromAlignedEvidence = try container.decode(Bool.self, forKey: .addVerificationOnlyFromAlignedEvidence)
        preferWindowOrContentRelativeCoordinates = try container.decode(Bool.self, forKey: .preferWindowOrContentRelativeCoordinates)
        preferContentNormalizedTextGeometry = try container.decodeIfPresent(Bool.self, forKey: .preferContentNormalizedTextGeometry)
            ?? (objective == .robust)
        preservePathSensitiveGestures = try container.decode(Bool.self, forKey: .preservePathSensitiveGestures)
        prohibitUnsupportedVisualLocators = try container.decode(Bool.self, forKey: .prohibitUnsupportedVisualLocators)
    }
}

public enum MacroCandidateDisposition: String, Codable, Equatable, CaseIterable, Sendable {
    case preserved, merged, replacedByLocator, replacedByWait, removedAsNoise, unresolved
}

public struct MacroCandidateCoverage: Codable, Equatable, Sendable {
    public var sourceActionID: String
    public var disposition: MacroCandidateDisposition
    public var candidateActionIDs: [String]
    public var reason: String

    public init(sourceActionID: String, disposition: MacroCandidateDisposition = .preserved,
                candidateActionIDs: [String] = [], reason: String = "") {
        self.sourceActionID = sourceActionID
        self.disposition = disposition
        self.candidateActionIDs = candidateActionIDs
        self.reason = reason
    }
}

/// A complete authoring document. Uncertainty is retained for review; validation
/// permits a test, while promotion must separately resolve or acknowledge it.
public struct MacroCandidateDocument: Codable, Equatable, Sendable {
    public var macro: SavedMacro
    public var sourceRevision: String
    public var summary: String
    public var coverage: [MacroCandidateCoverage]
    public var uncertainActionIDs: [String]
    public var model: String

    public init(macro: SavedMacro, sourceRevision: String = "", summary: String = "",
                coverage: [MacroCandidateCoverage] = [], uncertainActionIDs: [String] = [], model: String = "") {
        self.macro = macro
        self.sourceRevision = sourceRevision
        self.summary = summary
        self.coverage = coverage
        self.uncertainActionIDs = uncertainActionIDs
        self.model = model
    }

    public var requiresAttention: Bool {
        !uncertainActionIDs.isEmpty || coverage.contains { $0.disposition == .unresolved }
    }
}

public struct MacroCandidateSurfaceAuthoringPolicy: Codable, Equatable, Sendable {
    public let sourceSurfacesAreReadOnly: Bool
    public let sourceSurfacesAreOmittedFromCandidate: Bool
    public let eventSurfaceReferencesMayChange: Bool
    public let textOperationsRequireExplicitSurface: Bool
    public let liveSurfaceRebindingIsAppOwned: Bool

    public init(
        sourceSurfacesAreReadOnly: Bool,
        sourceSurfacesAreOmittedFromCandidate: Bool,
        eventSurfaceReferencesMayChange: Bool,
        textOperationsRequireExplicitSurface: Bool,
        liveSurfaceRebindingIsAppOwned: Bool
    ) {
        self.sourceSurfacesAreReadOnly = sourceSurfacesAreReadOnly
        self.sourceSurfacesAreOmittedFromCandidate = sourceSurfacesAreOmittedFromCandidate
        self.eventSurfaceReferencesMayChange = eventSurfaceReferencesMayChange
        self.textOperationsRequireExplicitSurface = textOperationsRequireExplicitSurface
        self.liveSurfaceRebindingIsAppOwned = liveSurfaceRebindingIsAppOwned
    }
}

public struct MacroCandidateTextOperationPolicy: Codable, Equatable, Sendable {
    public let locatorMouseEventsRequireTargetWindowBinding: Bool
    public let locatorMouseEventsRequireLocatorOnlyStrategy: Bool
    public let pointerGestureRequiresStableLocatorIdentity: Bool
    public let waitAndVerifyRequireBoundedTimeout: Bool
    public let verificationIsSingleObservation: Bool

    public init(
        locatorMouseEventsRequireTargetWindowBinding: Bool,
        locatorMouseEventsRequireLocatorOnlyStrategy: Bool,
        pointerGestureRequiresStableLocatorIdentity: Bool,
        waitAndVerifyRequireBoundedTimeout: Bool,
        verificationIsSingleObservation: Bool
    ) {
        self.locatorMouseEventsRequireTargetWindowBinding = locatorMouseEventsRequireTargetWindowBinding
        self.locatorMouseEventsRequireLocatorOnlyStrategy = locatorMouseEventsRequireLocatorOnlyStrategy
        self.pointerGestureRequiresStableLocatorIdentity = pointerGestureRequiresStableLocatorIdentity
        self.waitAndVerifyRequireBoundedTimeout = waitAndVerifyRequireBoundedTimeout
        self.verificationIsSingleObservation = verificationIsSingleObservation
    }
}

/// This manifest describes RecordedEvent playback, not the broader automation
/// condition vocabulary. Text verification is a single observation, not stability.
public struct MacroCandidateCapabilities: Codable, Equatable, Sendable {
    public let version: String
    public let macroVersions: [Int]
    public let eventKinds: [Int]
    public let locatorKinds: [String]
    public let authoringMacroFields: [String]
    public let eventFields: [String]
    /// Core non-optional RecordedEvent fields that must be present in every authored event.
    /// Optional so older exported authoring contracts remain decodable.
    public let requiredEventFields: [String]?
    public let textAnchorFields: [String]
    public let maximumEventCount: Int
    public let maximumDuration: Double
    public let maximumTextTimeout: Double
    public let maximumCoordinateMagnitude: Double
    public let normalizedCoordinateRange: [Double]
    public let surfaceAuthoringPolicy: MacroCandidateSurfaceAuthoringPolicy
    public let textOperationPolicy: MacroCandidateTextOperationPolicy
    public let textVerificationPolicy: String
    public let candidateActionRevision: String
    public let protectedExecutionFields: [String]

    public static let current = MacroCandidateCapabilities(
        version: MacroReconstructionContractVersions.candidateCapability, macroVersions: [3],
        eventKinds: RecordedEvent.Kind.allCases.map(\.rawValue),
        locatorKinds: ["text"], authoringMacroFields: MacroCandidateSchema.authoringMacroFields.sorted(),
        eventFields: MacroCandidateSchema.eventFields.sorted(),
        requiredEventFields: MacroCandidateSchema.requiredEventFields.sorted(),
        textAnchorFields: MacroCandidateSchema.anchorFields.sorted(),
        maximumEventCount: 100_000, maximumDuration: 86_400, maximumTextTimeout: 3_600,
        maximumCoordinateMagnitude: 1_000_000, normalizedCoordinateRange: [0, 1],
        surfaceAuthoringPolicy: MacroCandidateSurfaceAuthoringPolicy(
            sourceSurfacesAreReadOnly: true,
            sourceSurfacesAreOmittedFromCandidate: true,
            eventSurfaceReferencesMayChange: true,
            textOperationsRequireExplicitSurface: true,
            liveSurfaceRebindingIsAppOwned: true
        ),
        textOperationPolicy: MacroCandidateTextOperationPolicy(
            locatorMouseEventsRequireTargetWindowBinding: true,
            locatorMouseEventsRequireLocatorOnlyStrategy: true,
            pointerGestureRequiresStableLocatorIdentity: true,
            waitAndVerifyRequireBoundedTimeout: true,
            verificationIsSingleObservation: true
        ),
        textVerificationPolicy: "single observation; explicit positive bounded textTimeout; no stability guarantee",
        candidateActionRevision: MacroReconstructionContractVersions.candidateActionRevision,
        protectedExecutionFields: ["loops", "speed", "followWindowOffset", "chainTo"]
    )

    /// Older v4 reconstruction packages predate `requiredEventFields`. That field
    /// documents an already-enforced Codable requirement; it did not change playback
    /// semantics, so those packages remain safe to import when every other capability
    /// agrees with the current contract.
    public static func supportsImportVersion(_ version: String) -> Bool {
        version == current.version || version == "macro-candidate/v4"
    }

    public func isImportCompatibleWithCurrent() -> Bool {
        let expected = Self.current
        guard Self.supportsImportVersion(version) else { return false }
        guard macroVersions == expected.macroVersions,
              eventKinds == expected.eventKinds,
              locatorKinds == expected.locatorKinds,
              authoringMacroFields == expected.authoringMacroFields,
              eventFields == expected.eventFields,
              textAnchorFields == expected.textAnchorFields,
              maximumEventCount == expected.maximumEventCount,
              maximumDuration == expected.maximumDuration,
              maximumTextTimeout == expected.maximumTextTimeout,
              maximumCoordinateMagnitude == expected.maximumCoordinateMagnitude,
              normalizedCoordinateRange == expected.normalizedCoordinateRange,
              surfaceAuthoringPolicy == expected.surfaceAuthoringPolicy,
              textOperationPolicy == expected.textOperationPolicy,
              textVerificationPolicy == expected.textVerificationPolicy,
              candidateActionRevision == expected.candidateActionRevision,
              protectedExecutionFields == expected.protectedExecutionFields else {
            return false
        }
        return requiredEventFields == nil || requiredEventFields == expected.requiredEventFields
    }
}

// Shared with the strict JSON boundary so the exported manifest cannot drift.
enum MacroCandidateSchema {
    /// External authoring JSON exposes only executable content plus the minimum
    /// SavedMacro identity required for lossless decoding. Library placement,
    /// personalization, execution policy, statistics, caches and evidence links
    /// remain app-owned and are restored from the accepted source.
    static let authoringMacroFields: Set<String> = [
        "id", "name", "events", "createdAt", "modifiedAt", "version"
    ]
    /// Compatibility-only input accepted from v3 standalone candidates. New v4
    /// packages omit source-owned Surface bodies and reference them by event.surfaceId.
    static let acceptedMacroFields = authoringMacroFields.union(["surfaces"])
    static let requiredEventFields: Set<String> = [
        "kind", "time", "x", "y", "keyCode", "flags", "mouseButton", "clickCount", "scrollDeltaY", "scrollDeltaX"
    ]
    static let eventFields: Set<String> = requiredEventFields.union([
        "scrollPayload", "unicodeString", "windowLocalX", "windowLocalY", "windowNormalizedX", "windowNormalizedY",
        "contentLocalX", "contentLocalY", "contentNormalizedX", "contentNormalizedY", "coordinateBinding",
        "coordinateStrategy", "locatorFallbackPolicy", "surfaceId", "textAnchor", "textTimeout", "verifyMustExist",
        "behaviorGroupID", "behaviorGroupName", "isDisabled"
    ])
    static let anchorFields: Set<String> = [
        "text", "matchMode", "observedFrame", "searchRegion", "occurrenceHint", "coordinateFallback",
        "observedContentNormalizedFrame", "searchContentNormalizedRegion", "coordinateFallbackContentNormalized"
    ]
    static let surfaceFields: Set<String> = [
        "appName", "bundleIdentifier", "windowTitle", "recordedFrame", "recordedContentFrame", "contentElementRole",
        "contentElementSubrole", "capturedAt", "windowTitlePattern", "recordedDisplayId", "recordedWindowId", "contentFrameSource"
    ]
}
