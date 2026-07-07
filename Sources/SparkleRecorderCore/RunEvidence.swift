import Foundation

public struct RunReport: Codable, Equatable, Sendable {
    public var runID: UUID
    public var startTime: Date
    public var duration: TimeInterval
    public var isSuccess: Bool
    public var failedEventIndex: Int?
    public var errorMessage: String?
    
    public init(
        runID: UUID = UUID(),
        startTime: Date = Date.now,
        duration: TimeInterval = 0,
        isSuccess: Bool = true,
        failedEventIndex: Int? = nil,
        errorMessage: String? = nil
    ) {
        self.runID = runID
        self.startTime = startTime
        self.duration = max(0, duration)
        self.isSuccess = isSuccess
        self.failedEventIndex = failedEventIndex
        self.errorMessage = errorMessage
    }

    public init(failure evidence: PlaybackFailureEvidence) {
        self.init(
            runID: evidence.runID,
            startTime: evidence.startTime,
            duration: evidence.duration,
            isSuccess: false,
            failedEventIndex: evidence.failedEventIndex,
            errorMessage: evidence.errorMessage
        )
    }
}

public struct RunEvidenceManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var evidenceID: UUID
    public var macroID: UUID
    public var runID: UUID
    public var reportFilename: String
    public var screenshotFilename: String?
    public var createdAt: Date

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        evidenceID: UUID,
        macroID: UUID,
        runID: UUID,
        reportFilename: String = "report.json",
        screenshotFilename: String? = nil,
        createdAt: Date = Date.now
    ) {
        self.schemaVersion = schemaVersion
        self.evidenceID = evidenceID
        self.macroID = macroID
        self.runID = runID
        self.reportFilename = reportFilename
        self.screenshotFilename = screenshotFilename
        self.createdAt = createdAt
    }
}

public struct PlaybackFailureEvidence: Codable, Equatable, Sendable {
    public var macroID: UUID
    public var runID: UUID
    public var startTime: Date
    public var duration: TimeInterval
    public var failedEventIndex: Int?
    public var errorMessage: String
    public var bundleIdentifier: String?
    public var windowTitle: String?

    public init(
        macroID: UUID,
        runID: UUID = UUID(),
        startTime: Date = Date.now,
        duration: TimeInterval,
        failedEventIndex: Int?,
        errorMessage: String,
        bundleIdentifier: String? = nil,
        windowTitle: String? = nil
    ) {
        self.macroID = macroID
        self.runID = runID
        self.startTime = startTime
        self.duration = max(0, duration)
        self.failedEventIndex = failedEventIndex
        self.errorMessage = errorMessage
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
    }

    public var report: RunReport {
        RunReport(failure: self)
    }
}
