import Testing
@testable import SparkleRecorder

@Suite("Automation External Signal Source State Tests")
struct AutomationExternalSignalSourceStateTests {
  @Test("An old signal load cannot overwrite a newer signal")
  func oldLoadCannotOverwriteNewSignal() throws {
    var state = AutomationExternalSignalSourceState()
    let requestAValue = state.beginLoad(signalName: "  A  ")
    let requestA = try #require(requestAValue)
    let requestBValue = state.beginLoad(signalName: "B")
    let requestB = try #require(requestBValue)

    let acceptedB = state.applyLoaded(true, request: requestB)
    let acceptedA = state.applyLoaded(false, request: requestA)

    #expect(acceptedB)
    #expect(!acceptedA)
    #expect(state.signalName == "B")
    #expect(state.isActive)
  }

  @Test("A user toggle wins over an in-flight load for the same signal")
  func userToggleInvalidatesInFlightLoad() throws {
    var state = AutomationExternalSignalSourceState()
    let loadValue = state.beginLoad(signalName: "signal")
    let load = try #require(loadValue)
    let writeValue = state.userSetActive(true, signalName: "signal")
    let write = try #require(writeValue)

    let acceptedLoad = state.applyLoaded(false, request: load)

    #expect(!acceptedLoad)
    #expect(state.isActive)
    #expect(write.signalName == "signal")
    #expect(write.isActive)
  }

  @Test("Empty signals reset local state without producing provider requests")
  func emptySignalProducesNoRequests() {
    var state = AutomationExternalSignalSourceState()
    _ = state.userSetActive(true, signalName: "existing")

    let load = state.beginLoad(signalName: "   ")
    let write = state.userSetActive(false, signalName: "\n\t")

    #expect(load == nil)
    #expect(write == nil)
    #expect(state.signalName.isEmpty)
    #expect(!state.isActive)
  }

  @Test("Provider requests capture trimmed signal identity")
  func requestsUseTrimmedSignalIdentity() throws {
    var state = AutomationExternalSignalSourceState()
    let loadValue = state.beginLoad(signalName: "  Release Ready  ")
    let load = try #require(loadValue)
    let writeValue = state.userSetActive(true, signalName: "  Release Ready  ")
    let write = try #require(writeValue)

    #expect(load.signalName == "Release Ready")
    #expect(write.signalName == "Release Ready")
  }
}
