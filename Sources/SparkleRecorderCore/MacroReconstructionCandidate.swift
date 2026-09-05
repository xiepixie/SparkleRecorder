import Foundation

public enum MacroCandidateDisposition: String, Codable, Equatable, Sendable {
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

/// This manifest describes RecordedEvent playback, not the broader automation
/// condition vocabulary. Text verification is a single observation, not stability.
public struct MacroCandidateCapabilities: Codable, Equatable, Sendable {
    public let version: String
    public let macroVersions: [Int]
    public let eventKinds: [Int]
    public let locatorKinds: [String]
    public let eventFields: [String]
    public let textAnchorFields: [String]
    public let maximumEventCount: Int
    public let maximumDuration: Double
    public let maximumTextTimeout: Double
    public let maximumCoordinateMagnitude: Double
    public let normalizedCoordinateRange: [Double]
    public let textVerificationPolicy: String
    public let candidateActionRevision: String
    public let protectedExecutionFields: [String]

    public static let current = MacroCandidateCapabilities(
        version: "macro-candidate/v1", macroVersions: [3],
        eventKinds: [1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 22, 25, 26, 27, 100, 101],
        locatorKinds: ["text"], eventFields: MacroCandidateSchema.eventFields.sorted(),
        textAnchorFields: MacroCandidateSchema.anchorFields.sorted(),
        maximumEventCount: 100_000, maximumDuration: 86_400, maximumTextTimeout: 3_600,
        maximumCoordinateMagnitude: 1_000_000, normalizedCoordinateRange: [0, 1],
        textVerificationPolicy: "single observation; explicit positive bounded textTimeout; no stability guarantee",
        candidateActionRevision: "candidate",
        protectedExecutionFields: ["loops", "speed", "followWindowOffset", "chainTo"]
    )
}

// Shared with the strict JSON boundary so the exported manifest cannot drift.
enum MacroCandidateSchema {
    static let eventFields: Set<String> = [
        "kind", "time", "x", "y", "keyCode", "flags", "mouseButton", "clickCount", "scrollDeltaY", "scrollDeltaX",
        "scrollPayload", "unicodeString", "windowLocalX", "windowLocalY", "windowNormalizedX", "windowNormalizedY",
        "contentLocalX", "contentLocalY", "contentNormalizedX", "contentNormalizedY", "coordinateBinding",
        "coordinateStrategy", "locatorFallbackPolicy", "surfaceId", "textAnchor", "textTimeout", "verifyMustExist",
        "behaviorGroupID", "behaviorGroupName", "isDisabled"
    ]
    static let anchorFields: Set<String> = [
        "text", "matchMode", "observedFrame", "searchRegion", "occurrenceHint", "coordinateFallback",
        "observedContentNormalizedFrame", "searchContentNormalizedRegion", "coordinateFallbackContentNormalized"
    ]
    static let surfaceFields: Set<String> = [
        "appName", "bundleIdentifier", "windowTitle", "recordedFrame", "recordedContentFrame", "contentElementRole",
        "contentElementSubrole", "capturedAt", "windowTitlePattern", "recordedDisplayId", "recordedWindowId", "contentFrameSource"
    ]
}
