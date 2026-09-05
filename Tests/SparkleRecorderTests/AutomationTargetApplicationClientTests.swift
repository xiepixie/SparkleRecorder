import Foundation
import Testing

@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Target Application Client Tests")
struct AutomationTargetApplicationClientTests {
  @Test("Cleanup only selects applications recorded as launched by the run")
  func cleanupOnlySelectsRunLaunchedApplications() {
    let session = AutomationTargetApplicationSession(
      launchedApplications: [
        .init(bundleIdentifier: "com.example.B", processIdentifier: 22),
        .init(bundleIdentifier: "com.example.A", processIdentifier: 11),
      ]
    )

    #expect(session.applicationsToQuit(under: .keepOpen).isEmpty)
    #expect(
      session.applicationsToQuit(under: .quitIfLaunched).map(\.processIdentifier) == [11, 22])
    #expect(
      AutomationTargetApplicationSession.empty
        .applicationsToQuit(under: .quitIfLaunched)
        .isEmpty)
  }

  @Test("Cleanup force quits the exact launched process after graceful timeout")
  @MainActor
  func cleanupForceQuitsAfterTimeout() async {
    let probe = ApplicationProcessProbe(waitResults: [false, true])
    let client = AutomationTargetApplicationClient.live(
      windowTracker: nil,
      processClient: probe.client
    )
    let result = await client.cleanup(
      .init(launchedApplications: [
        .init(bundleIdentifier: "com.example.Target", processIdentifier: 42)
      ]),
      .quitIfLaunched,
      5,
      true
    )

    #expect(result.forceTerminated == [42])
    #expect(result.unresolved.isEmpty)
    #expect(await probe.terminated == [42])
    #expect(await probe.forceTerminated == [42])
    #expect(await probe.waitTimeouts == [5, 2])
  }

  @Test("Cleanup leaves a timed out process unresolved when force quit is disabled")
  @MainActor
  func cleanupRespectsGracefulOnlyChoice() async {
    let probe = ApplicationProcessProbe(waitResults: [false])
    let client = AutomationTargetApplicationClient.live(
      windowTracker: nil,
      processClient: probe.client
    )
    let result = await client.cleanup(
      .init(launchedApplications: [
        .init(bundleIdentifier: "com.example.Target", processIdentifier: 43)
      ]),
      .quitIfLaunched,
      10,
      false
    )

    #expect(result.unresolved == [43])
    #expect(await probe.terminated == [43])
    #expect(await probe.forceTerminated.isEmpty)
  }

  @Test("Player rejects a run when target application preparation fails")
  @MainActor
  func playerRejectsFailedTargetPreparation() async throws {
    let macro = SavedMacro(
      name: "Bound task",
      events: TestFixtures.clickPair(),
      surfaces: [
        TestFixtures.surfaceId: TestFixtures.surface(
          appName: "Target App",
          bundleIdentifier: "com.example.TargetApp",
          windowTitle: "Target"
        )
      ]
    )
    let recorder = TargetApplicationPreparationRecorder()
    let cleanupRecorder = TargetApplicationCleanupRecorder()
    let targetApplications = AutomationTargetApplicationClient(
      prepare: { surfaces, policy in
        await recorder.record(surfaces: surfaces, policy: policy)
        return .failure(
          .init(
            message: "Target window unavailable",
            session: .init(launchedApplications: [
              .init(bundleIdentifier: "com.example.TargetApp", processIdentifier: 77)
            ])
          ))
      },
      cleanup: { session, policy, timeout, forceQuitOnTimeout in
        await cleanupRecorder.record(
          session: session,
          policy: policy,
          timeout: timeout,
          forceQuitOnTimeout: forceQuitOnTimeout
        )
        return .init(gracefullyTerminated: [77])
      }
    )
    let player = AutomationPlayerClient.live(
      player: Player(),
      targetApplications: targetApplications
    )

    let result = await player.start(
      AutomationPlayerStartRequest(
        runID: UUID(),
        macro: macro,
        targetApplicationPolicy: .launchIfNeeded,
        targetApplicationCleanupPolicy: .quitIfLaunched,
        targetApplicationQuitTimeout: 10,
        targetApplicationForceQuitOnTimeout: false
      ))

    #expect(result == .rejected(.rejected(reason: "Target window unavailable")))
    #expect(await recorder.policies == [.launchIfNeeded])
    #expect(await recorder.surfaceCounts == [1])
    #expect(await cleanupRecorder.processIdentifiers == [[77]])
    #expect(await cleanupRecorder.policies == [.quitIfLaunched])
    #expect(await cleanupRecorder.timeouts == [10])
    #expect(await cleanupRecorder.forceQuitChoices == [false])
  }

  @Test("Cancelling startup readiness prevents playback and cleans the launched process")
  @MainActor
  func cancellationDuringReadinessCleansTargetWithoutPlayback() async throws {
    let runID = UUID()
    let macro = SavedMacro(
      name: "Prepared task",
      events: TestFixtures.clickPair()
    )
    let playerInstance = Player()
    let waitProbe = ReadinessWaitProbe()
    let cleanupRecorder = TargetApplicationCleanupRecorder()
    let targetApplications = AutomationTargetApplicationClient(
      prepare: { _, _ in
        .success(
          .init(launchedApplications: [
            .init(bundleIdentifier: "com.example.TargetApp", processIdentifier: 88)
          ]))
      },
      cleanup: { session, policy, timeout, forceQuitOnTimeout in
        await cleanupRecorder.record(
          session: session,
          policy: policy,
          timeout: timeout,
          forceQuitOnTimeout: forceQuitOnTimeout
        )
        return .init(gracefullyTerminated: [88])
      }
    )
    let player = AutomationPlayerClient.live(
      player: playerInstance,
      targetApplications: targetApplications,
      readinessSleep: { duration in
        await waitProbe.wait(duration: duration)
      }
    )
    let startTask = Task { @MainActor in
      await player.start(
        AutomationPlayerStartRequest(
          runID: runID,
          macro: macro,
          targetApplicationPolicy: .launchIfNeeded,
          targetApplicationReadyDelay: 10,
          targetApplicationCleanupPolicy: .quitIfLaunched
        ))
    }

    await waitProbe.waitUntilStarted()
    await player.cancel(runID)
    await waitProbe.release()
    let result = await startTask.value

    #expect(
      result
        == .rejected(
          .cancelled(reason: "Automation cancelled during startup preparation")))
    #expect(!playerInstance.isPlaying)
    #expect(await waitProbe.durations == [10])
    #expect(await cleanupRecorder.processIdentifiers == [[88]])
  }
}

private actor ReadinessWaitProbe {
  private var recordedDurations: [TimeInterval] = []
  private var startedWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
  private var didStart = false
  private var didRelease = false

  var durations: [TimeInterval] { recordedDurations }

  func wait(duration: TimeInterval) async {
    recordedDurations.append(duration)
    didStart = true
    let waiters = startedWaiters
    startedWaiters.removeAll()
    waiters.forEach { $0.resume() }
    guard !didRelease else { return }
    await withCheckedContinuation { continuation in
      releaseWaiters.append(continuation)
    }
  }

  func waitUntilStarted() async {
    guard !didStart else { return }
    await withCheckedContinuation { continuation in
      startedWaiters.append(continuation)
    }
  }

  func release() {
    didRelease = true
    let waiters = releaseWaiters
    releaseWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }
}

private actor TargetApplicationCleanupRecorder {
  private var recordedProcessIdentifiers: [[pid_t]] = []
  private var recordedPolicies: [AutomationTargetApplicationCleanupPolicy] = []
  private var recordedTimeouts: [TimeInterval] = []
  private var recordedForceQuitChoices: [Bool] = []

  var processIdentifiers: [[pid_t]] { recordedProcessIdentifiers }
  var policies: [AutomationTargetApplicationCleanupPolicy] { recordedPolicies }
  var timeouts: [TimeInterval] { recordedTimeouts }
  var forceQuitChoices: [Bool] { recordedForceQuitChoices }

  func record(
    session: AutomationTargetApplicationSession,
    policy: AutomationTargetApplicationCleanupPolicy,
    timeout: TimeInterval,
    forceQuitOnTimeout: Bool
  ) {
    recordedProcessIdentifiers.append(
      session.applicationsToQuit(under: policy).map(\.processIdentifier))
    recordedPolicies.append(policy)
    recordedTimeouts.append(timeout)
    recordedForceQuitChoices.append(forceQuitOnTimeout)
  }
}

private actor ApplicationProcessProbe {
  private var remainingWaitResults: [Bool]
  private var recordedTerminated: [pid_t] = []
  private var recordedForceTerminated: [pid_t] = []
  private var recordedWaitTimeouts: [TimeInterval] = []

  init(waitResults: [Bool]) {
    self.remainingWaitResults = waitResults
  }

  var terminated: [pid_t] { recordedTerminated }
  var forceTerminated: [pid_t] { recordedForceTerminated }
  var waitTimeouts: [TimeInterval] { recordedWaitTimeouts }

  nonisolated var client: AutomationApplicationProcessClient {
    AutomationApplicationProcessClient(
      terminate: { processIdentifier in
        await self.recordTerminate(processIdentifier)
        return true
      },
      forceTerminate: { processIdentifier in
        await self.recordForceTerminate(processIdentifier)
        return true
      },
      waitUntilTerminated: { _, timeout in
        await self.nextWaitResult(timeout: timeout)
      }
    )
  }

  private func recordTerminate(_ processIdentifier: pid_t) {
    recordedTerminated.append(processIdentifier)
  }

  private func recordForceTerminate(_ processIdentifier: pid_t) {
    recordedForceTerminated.append(processIdentifier)
  }

  private func nextWaitResult(timeout: TimeInterval) -> Bool {
    recordedWaitTimeouts.append(timeout)
    guard !remainingWaitResults.isEmpty else { return false }
    return remainingWaitResults.removeFirst()
  }
}

private actor TargetApplicationPreparationRecorder {
  private var recordedPolicies: [AutomationTargetApplicationPolicy] = []
  private var recordedSurfaceCounts: [Int] = []

  var policies: [AutomationTargetApplicationPolicy] { recordedPolicies }
  var surfaceCounts: [Int] { recordedSurfaceCounts }

  func record(
    surfaces: [String: PlaybackSurface],
    policy: AutomationTargetApplicationPolicy
  ) {
    recordedPolicies.append(policy)
    recordedSurfaceCounts.append(surfaces.count)
  }
}
