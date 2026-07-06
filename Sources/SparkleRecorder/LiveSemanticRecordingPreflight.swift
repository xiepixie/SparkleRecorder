import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.hid
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

    static let liveCommandLine = SemanticRecordingPreflightClient {
        SemanticRecordingPermissionSnapshot(
            inputMonitoring: SemanticRecordingPermissionState(
                semanticRecordingCheckListenEventAccess()
            ),
            accessibility: SemanticRecordingPermissionState(
                semanticRecordingCheckAccessibilityAccess()
            ),
            screenRecording: SemanticRecordingPermissionState(
                semanticRecordingCheckScreenCaptureAccess()
            )
        )
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

private func semanticRecordingCheckListenEventAccess() -> PermissionStatus {
    if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted {
        return .authorized
    }

    if #available(macOS 14.4, *) {
        return CGPreflightListenEventAccess() ? .authorized : .denied
    } else {
        return .denied
    }
}

private func semanticRecordingCheckScreenCaptureAccess() -> PermissionStatus {
    if #available(macOS 10.15, *) {
        return CGPreflightScreenCaptureAccess() ? .authorized : .denied
    } else {
        return .authorized
    }
}

private func semanticRecordingCheckAccessibilityAccess() -> PermissionStatus {
    AXIsProcessTrusted() ? .authorized : .denied
}
