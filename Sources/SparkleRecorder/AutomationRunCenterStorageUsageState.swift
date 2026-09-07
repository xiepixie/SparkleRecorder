import Foundation

struct AutomationRunCenterStorageUsageState: Equatable, Sendable {
  struct RefreshID: Equatable, Hashable, Sendable {
    fileprivate let rawValue: UUID

    fileprivate init(rawValue: UUID = UUID()) {
      self.rawValue = rawValue
    }
  }

  private(set) var usage: AutomationRunStorageUsage?
  private(set) var errorMessage: String?
  private var activeRefreshID: RefreshID?

  mutating func beginRefresh() -> RefreshID {
    let refreshID = RefreshID()
    activeRefreshID = refreshID
    return refreshID
  }

  @discardableResult
  mutating func publish(
    _ usage: AutomationRunStorageUsage,
    for refreshID: RefreshID
  ) -> Bool {
    guard activeRefreshID == refreshID else {
      return false
    }
    self.usage = usage
    errorMessage = nil
    return true
  }

  @discardableResult
  mutating func publishFailure(
    _ message: String,
    for refreshID: RefreshID
  ) -> Bool {
    guard activeRefreshID == refreshID else {
      return false
    }
    usage = nil
    errorMessage = message
    return true
  }
}
