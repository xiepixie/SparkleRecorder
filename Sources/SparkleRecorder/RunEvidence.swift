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
