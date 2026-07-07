import Foundation

public struct AutomationStatusCount: Identifiable, Codable, Equatable, Sendable {
    public var id: AutomationDisplayStatus { status }

    public var status: AutomationDisplayStatus
    public var count: Int

    public init(status: AutomationDisplayStatus, count: Int) {
        self.status = status
        self.count = max(0, count)
    }
}
