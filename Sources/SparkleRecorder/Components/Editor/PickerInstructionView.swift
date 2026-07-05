import Cocoa
import SwiftUI
import SparkleRecorderCore

struct PickerInstructionView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "scope")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Double-click anywhere to pick coordinate", comment: ""))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text(NSLocalizedString("Press ESC to cancel", comment: ""))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 8)
    }
}
