import AppKit
import SwiftUI

struct AutomationTaskRunEvidenceScreenshotPreviewView: View {
    let screenshotData: Data
    let loadedAt: Date

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 128)
                    .background(Color.primary.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
                    )
                    .accessibilityLabel(String(localized: "Failure screenshot preview", table: "Common"))
            } else {
                Label(String(localized: "Screenshot preview unavailable", table: "Common"), systemImage: "photo.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: loadedAt) {
            image = NSImage(data: screenshotData)
        }
    }
}
