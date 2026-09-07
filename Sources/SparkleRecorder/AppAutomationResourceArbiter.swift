import Foundation
import SparkleRecorderCore

/// App-layer adapter that makes Automation's foreground-input lease respect
/// SparkleRecorder's own recording/manual-playback ownership.
///
/// The core arbiter still owns Automation-vs-Automation ordering and leases.
/// This adapter only denies a new foreground-input acquisition while the App
/// shell already owns the capture/input target. Other resources are unchanged.
enum AppAutomationResourceArbiter {
    static func make(
        base: AutomationResourceArbiterClient = .live(),
        foregroundInputAvailable: @escaping @Sendable () async -> Bool
    ) -> AutomationResourceArbiterClient {
        AutomationResourceArbiterClient(
            acquire: { request in
                if request.resource == .foregroundInput,
                   !(await foregroundInputAvailable()) {
                    return .denied(resource: .foregroundInput)
                }
                return await base.acquire(request)
            },
            release: base.release,
            panicRelease: base.panicRelease,
            releaseExpired: base.releaseExpired
        )
    }
}
