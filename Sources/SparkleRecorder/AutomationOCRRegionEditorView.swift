import SwiftUI
import SparkleRecorderCore

struct AutomationOCRRegionEditorView: View {
    let spaceTitle: String
    let statusTitle: String
    let statusDetail: String
    let statusImage: String
    let statusTint: Color
    let hasRegion: Bool
    let isNormalizedSpace: Bool
    let referenceSize: CGSize?
    @Binding var regionX: Double
    @Binding var regionY: Double
    @Binding var regionWidth: Double
    @Binding var regionHeight: Double
    let onPickText: () -> Void
    let onDraw: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(statusTitle, systemImage: statusImage)
                .font(.caption)
                .foregroundStyle(statusTint)

            Text(statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            regionPreview

            if hasRegion {
                regionFields

                Button(action: onClear) {
                    Label(NSLocalizedString("Clear Region", comment: ""), systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .controlSurface(cornerRadius: 8, tint: Brand.red500, isActive: false)
            }

            HStack(spacing: 8) {
                Button(action: onPickText) {
                    Label(NSLocalizedString("Pick Text Region", comment: ""), systemImage: "text.viewfinder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .controlSurface(cornerRadius: 8, tint: Brand.sigAmber, isActive: false)

                Button(action: onDraw) {
                    Label(NSLocalizedString("Draw Region", comment: ""), systemImage: "viewfinder.rectangular")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .controlSurface(cornerRadius: 8, tint: Brand.libraryBlue, isActive: false)
            }
        }
    }

    private var regionPreview: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))

                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)

                if let previewRect = previewRect(in: proxy.size) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Brand.sigAmber.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Brand.sigAmber, lineWidth: 1.4)
                        )
                        .frame(width: previewRect.width, height: previewRect.height)
                        .offset(x: previewRect.minX, y: previewRect.minY)
                } else {
                    Label(NSLocalizedString("No region selected", comment: ""), systemImage: "viewfinder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(height: 88)
        .accessibilityLabel(previewAccessibilityLabel)
    }

    private var regionFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Region bounds", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                numericField(NSLocalizedString("X", comment: ""), value: $regionX)
                numericField(NSLocalizedString("Y", comment: ""), value: $regionY)
            }

            HStack(spacing: 8) {
                numericField(NSLocalizedString("W", comment: ""), value: $regionWidth)
                numericField(NSLocalizedString("H", comment: ""), value: $regionHeight)
            }
        }
    }

    private func numericField(_ label: String, value: Binding<Double>) -> some View {
        LabeledContent(label) {
            TextField(label, value: value, format: .number.precision(.fractionLength(isNormalizedSpace ? 3 : 0)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
        }
        .font(.caption)
    }

    private func previewRect(in size: CGSize) -> CGRect? {
        guard hasRegion, regionWidth > 0, regionHeight > 0 else {
            return nil
        }

        let reference = effectiveReferenceSize
        guard reference.width > 0, reference.height > 0 else {
            return nil
        }

        let normalizedX = isNormalizedSpace ? regionX : regionX / reference.width
        let normalizedY = isNormalizedSpace ? regionY : regionY / reference.height
        let normalizedWidth = isNormalizedSpace ? regionWidth : regionWidth / reference.width
        let normalizedHeight = isNormalizedSpace ? regionHeight : regionHeight / reference.height

        let x = min(max(normalizedX, 0), 1)
        let y = min(max(normalizedY, 0), 1)
        let width = min(max(normalizedWidth, 0.02), 1 - x)
        let height = min(max(normalizedHeight, 0.02), 1 - y)

        return CGRect(
            x: x * size.width,
            y: y * size.height,
            width: max(8, width * size.width),
            height: max(8, height * size.height)
        )
    }

    private var effectiveReferenceSize: CGSize {
        if let referenceSize, referenceSize.width > 0, referenceSize.height > 0 {
            return referenceSize
        }

        return CGSize(
            width: max(regionX + regionWidth, 1),
            height: max(regionY + regionHeight, 1)
        )
    }

    private var previewAccessibilityLabel: String {
        guard hasRegion else {
            return NSLocalizedString("No region selected", comment: "")
        }

        return String(
            format: NSLocalizedString("%@ region: x %@, y %@, width %@, height %@", comment: ""),
            spaceTitle,
            formatted(regionX),
            formatted(regionY),
            formatted(regionWidth),
            formatted(regionHeight)
        )
    }

    private func formatted(_ value: Double) -> String {
        if isNormalizedSpace {
            return value.formatted(.number.precision(.fractionLength(3)))
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
}
