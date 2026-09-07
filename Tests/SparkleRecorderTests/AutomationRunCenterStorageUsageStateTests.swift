import Foundation
import Testing
@testable import SparkleRecorder

@Suite("Automation Run Center Storage Usage State Tests")
struct AutomationRunCenterStorageUsageStateTests {
  @Test("A slower old storage refresh cannot overwrite a newer success")
  func staleSuccessIsIgnored() {
    var state = AutomationRunCenterStorageUsageState()
    let oldRefresh = state.beginRefresh()
    let newRefresh = state.beginRefresh()

    let newUsage = usage(totalEvidenceBytes: 200)
    let oldUsage = usage(totalEvidenceBytes: 100)

    let acceptedNew = state.publish(newUsage, for: newRefresh)
    let acceptedOld = state.publish(oldUsage, for: oldRefresh)
    #expect(acceptedNew)
    #expect(!acceptedOld)
    #expect(state.usage == newUsage)
    #expect(state.errorMessage == nil)
  }

  @Test("A stale storage failure cannot erase a newer success")
  func staleFailureIsIgnored() {
    var state = AutomationRunCenterStorageUsageState()
    let oldRefresh = state.beginRefresh()
    let newRefresh = state.beginRefresh()
    let newUsage = usage(totalEvidenceBytes: 240)

    let acceptedNew = state.publish(newUsage, for: newRefresh)
    let acceptedOldFailure = state.publishFailure("old failure", for: oldRefresh)
    #expect(acceptedNew)
    #expect(!acceptedOldFailure)
    #expect(state.usage == newUsage)
    #expect(state.errorMessage == nil)
  }

  @Test("The latest storage failure replaces stale usage until a newer refresh succeeds")
  func latestFailureAndRecovery() {
    var state = AutomationRunCenterStorageUsageState()
    let firstRefresh = state.beginRefresh()
    let firstUsage = usage(totalEvidenceBytes: 80)
    let acceptedFirst = state.publish(firstUsage, for: firstRefresh)
    #expect(acceptedFirst)

    let failedRefresh = state.beginRefresh()
    let acceptedFailure = state.publishFailure("unavailable", for: failedRefresh)
    #expect(acceptedFailure)
    #expect(state.usage == nil)
    #expect(state.errorMessage == "unavailable")

    let recoveryRefresh = state.beginRefresh()
    let recoveredUsage = usage(totalEvidenceBytes: 60)
    let acceptedRecovery = state.publish(recoveredUsage, for: recoveryRefresh)
    #expect(acceptedRecovery)
    #expect(state.usage == recoveredUsage)
    #expect(state.errorMessage == nil)
  }

  private func usage(totalEvidenceBytes: Int64) -> AutomationRunStorageUsage {
    AutomationRunStorageUsage(
      breakdown: AutomationRunStorageBreakdown(reportByteCount: totalEvidenceBytes),
      historyByteCount: 0,
      runCount: 1,
      executionBreakdowns: [:]
    )
  }
}
