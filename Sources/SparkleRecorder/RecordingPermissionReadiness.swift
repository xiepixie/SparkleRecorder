enum RecordingEvidenceMode: Equatable, Sendable {
    case actionsOnly
    case actionsAndVisualEvidence
    case visualEvidenceBlocked
}

struct RecordingPermissionReadiness: Equatable, Sendable {
    let accessibilityGranted: Bool
    let inputMonitoringGranted: Bool
    let screenCaptureGranted: Bool
    let visualEvidenceEnabled: Bool

    var canRecordInputs: Bool {
        inputMonitoringGranted
    }

    var canReplay: Bool {
        accessibilityGranted
    }

    var canRecordAndReplay: Bool {
        canRecordInputs && canReplay
    }

    var shouldStopActiveRecording: Bool {
        !canRecordInputs
    }

    var allEnabledFeaturesReady: Bool {
        canRecordAndReplay && (!visualEvidenceEnabled || screenCaptureGranted)
    }

    var evidenceMode: RecordingEvidenceMode {
        guard visualEvidenceEnabled else { return .actionsOnly }
        return screenCaptureGranted ? .actionsAndVisualEvidence : .visualEvidenceBlocked
    }
}
