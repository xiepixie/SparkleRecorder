import Foundation
import SparkleRecorderCore

extension SemanticRecordingPreflightClient {
    static let live = SemanticRecordingPreflightClient {
        await MainActor.run {
            SemanticRecordingPermissionSnapshot(
                inputMonitoring: SemanticRecordingPermissionState(
                    PermissionCenter.shared.checkListenEventAccess()
                ),
                accessibility: SemanticRecordingPermissionState(
                    PermissionCenter.shared.checkAccessibilityAccess()
                ),
                screenRecording: SemanticRecordingPermissionState(
                    PermissionCenter.shared.checkScreenCaptureAccess()
                )
            )
        }
    }
}

private extension SemanticRecordingPermissionState {
    init(_ status: PermissionStatus) {
        switch status {
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .notDetermined:
            self = .notDetermined
        }
    }
}
