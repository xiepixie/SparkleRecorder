import SwiftUI

struct BrandTitleStrip: View {
    var body: some View {
        HStack(spacing: 7) {
            BrandMark(size: 20)
            Wordmark(size: 13)
        }
        .padding(.leading, 7)
        .padding(.trailing, 10)
        .frame(height: 28)
        .background {
            Capsule(style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(LinearGradient(
                            colors: [
                                Brand.libraryBlue.opacity(0.12),
                                Brand.sigTeal.opacity(0.045),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                )
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        Brand.libraryBlue.opacity(0.22),
                        Color.primary.opacity(0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SparkleRecorder")
    }
}
