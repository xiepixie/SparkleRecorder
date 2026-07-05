import Foundation

public struct RunReport: Codable, Sendable {
    public var runID: UUID
    public var startTime: Date
    public var duration: TimeInterval
    public var isSuccess: Bool
    public var failedEventIndex: Int?
    public var errorMessage: String?
    
    public init(runID: UUID = UUID(), startTime: Date = Date(), duration: TimeInterval = 0, isSuccess: Bool = true, failedEventIndex: Int? = nil, errorMessage: String? = nil) {
        self.runID = runID
        self.startTime = startTime
        self.duration = duration
        self.isSuccess = isSuccess
        self.failedEventIndex = failedEventIndex
        self.errorMessage = errorMessage
    }
}
