import Foundation
import IOKit.pwr_mgt

final class PlaybackPowerAssertion: @unchecked Sendable {
    private let reason: String
    private let userActivityRefreshInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.sparklerecorder.playback-power-assertion")
    private let queueKey = DispatchSpecificKey<Bool>()

    private var activity: NSObjectProtocol?
    private var assertionIDs: [IOPMAssertionID] = []
    private var userActivityAssertionID: IOPMAssertionID = 0
    private var userActivityTimer: DispatchSourceTimer?
    private var didEnd = false

    init(
        reason: String = "SparkleRecorder Playback",
        userActivityRefreshInterval: TimeInterval = 20
    ) {
        self.reason = reason
        self.userActivityRefreshInterval = max(1, userActivityRefreshInterval)
        queue.setSpecific(key: queueKey, value: true)
        queue.sync {
            beginOnQueue()
        }
    }

    deinit {
        end()
    }

    func end() {
        if DispatchQueue.getSpecific(key: queueKey) == true {
            endOnQueue()
        } else {
            queue.sync {
                endOnQueue()
            }
        }
    }

    private func beginOnQueue() {
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .idleDisplaySleepDisabled],
            reason: reason
        )
        createAssertionOnQueue(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString)
        createAssertionOnQueue(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString)
        declareUserActivityOnQueue()
        startUserActivityTimerOnQueue()
    }

    private func createAssertionOnQueue(_ type: CFString) {
        var assertionID: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        if status == kIOReturnSuccess, assertionID != 0 {
            assertionIDs.append(assertionID)
        }
    }

    private func declareUserActivityOnQueue() {
        guard !didEnd else { return }
        var assertionID = userActivityAssertionID
        let status = IOPMAssertionDeclareUserActivity(
            reason as CFString,
            kIOPMUserActiveLocal,
            &assertionID
        )
        if status == kIOReturnSuccess, assertionID != 0 {
            userActivityAssertionID = assertionID
        }
    }

    private func startUserActivityTimerOnQueue() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + userActivityRefreshInterval,
            repeating: userActivityRefreshInterval
        )
        timer.setEventHandler { [weak self] in
            self?.declareUserActivityOnQueue()
        }
        userActivityTimer = timer
        timer.resume()
    }

    private func endOnQueue() {
        guard !didEnd else { return }
        didEnd = true

        userActivityTimer?.setEventHandler {}
        userActivityTimer?.cancel()
        userActivityTimer = nil

        if userActivityAssertionID != 0 {
            IOPMAssertionRelease(userActivityAssertionID)
            userActivityAssertionID = 0
        }

        for assertionID in assertionIDs {
            IOPMAssertionRelease(assertionID)
        }
        assertionIDs.removeAll()

        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }
}
