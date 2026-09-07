import Cocoa
import SwiftUI
import SparkleRecorderCore

struct PermissionBanner: View {
    let controller: MenuBarController
    let accessibilityGranted: Bool
    let inputMonitoringGranted: Bool
    let screenCaptureGranted: Bool
    let visualEvidenceEnabled: Bool

    private var readiness: RecordingPermissionReadiness {
        RecordingPermissionReadiness(
            accessibilityGranted: accessibilityGranted,
            inputMonitoringGranted: inputMonitoringGranted,
            screenCaptureGranted: screenCaptureGranted,
            visualEvidenceEnabled: visualEvidenceEnabled
        )
    }

    private var detailText: String {
        if !readiness.canRecordAndReplay {
            return String(
                localized: "Grant Accessibility & Input Monitoring to record and replay.",
                table: "Recording"
            )
        }
        return String(
            localized: "Screen Recording is required while visual evidence is enabled.",
            table: "Recording"
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text("Permissions required", tableName: "Settings")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detailText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(String(localized: "Open", table: "Common")) {
                if !accessibilityGranted {
                    controller.openAccessibilityPrefs()
                } else if !inputMonitoringGranted {
                    controller.openInputMonitoringPrefs()
                } else if visualEvidenceEnabled && !screenCaptureGranted {
                    controller.openScreenCapturePrefs()
                }
            }
            .buttonStyle(PillButtonStyle(tint: .orange))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.45), lineWidth: 0.8)
                )
        )
    }
}
