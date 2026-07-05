import Cocoa
import SwiftUI
import SparkleRecorderCore

struct PermissionBanner: View {
    let controller: MenuBarController
    let accessibilityGranted: Bool
    let inputMonitoringGranted: Bool
    let screenCaptureGranted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Permissions required", comment: ""))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(NSLocalizedString("Grant Accessibility, Input Monitoring & Screen Recording to record and replay.", comment: ""))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(NSLocalizedString("Open", comment: "")) {
                if !accessibilityGranted {
                    controller.openAccessibilityPrefs()
                } else if !inputMonitoringGranted {
                    controller.openInputMonitoringPrefs()
                } else if !screenCaptureGranted {
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
