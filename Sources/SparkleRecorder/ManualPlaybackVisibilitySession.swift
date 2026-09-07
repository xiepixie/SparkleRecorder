import AppKit

/// Owns the SparkleRecorder window visibility snapshot for one user-initiated
/// playback chain. Chained macros share one session so the app stays out of the
/// way until the whole chain finishes, then the original windows/focus return.
@MainActor
final class ManualPlaybackVisibilitySession {
    typealias CaptureRestore = @MainActor () -> (@MainActor () -> Void)

    private let captureRestore: CaptureRestore
    private var restoreAction: (@MainActor () -> Void)?

    init(captureRestore: @escaping CaptureRestore = {
        let snapshot = ApplicationWindowVisibilitySnapshot.capture()
        return { snapshot.restore() }
    }) {
        self.captureRestore = captureRestore
    }

    var isActive: Bool { restoreAction != nil }

    func beginIfNeeded() {
        guard restoreAction == nil else { return }
        restoreAction = captureRestore()
    }

    func restore() {
        guard let restoreAction else { return }
        self.restoreAction = nil
        restoreAction()
    }
}
