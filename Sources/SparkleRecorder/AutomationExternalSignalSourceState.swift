import Foundation

struct AutomationExternalSignalSourceState: Equatable, Sendable {
  struct LoadRequest: Equatable, Sendable {
    let signalName: String
    fileprivate let generation: UInt64
  }

  struct WriteRequest: Equatable, Sendable {
    let signalName: String
    let isActive: Bool
  }

  private(set) var signalName: String = ""
  private(set) var isActive: Bool = false
  private var loadGeneration: UInt64 = 0

  mutating func beginLoad(signalName rawSignalName: String) -> LoadRequest? {
    loadGeneration &+= 1
    signalName = rawSignalName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !signalName.isEmpty else {
      isActive = false
      return nil
    }
    return LoadRequest(signalName: signalName, generation: loadGeneration)
  }

  @discardableResult
  mutating func applyLoaded(_ active: Bool, request: LoadRequest) -> Bool {
    guard request.generation == loadGeneration, request.signalName == signalName else {
      return false
    }
    isActive = active
    return true
  }

  mutating func userSetActive(
    _ active: Bool,
    signalName rawSignalName: String
  ) -> WriteRequest? {
    loadGeneration &+= 1
    signalName = rawSignalName.trimmingCharacters(in: .whitespacesAndNewlines)
    isActive = active
    guard !signalName.isEmpty else {
      return nil
    }
    return WriteRequest(signalName: signalName, isActive: active)
  }
}
