import SwiftUI
import SparkleRecorderCore

struct AutomationVisualConditionEditorView: View {
    let regionStatusTitle: String
    let regionStatusDetail: String
    let regionStatusImage: String
    let regionStatusTint: Color
    let referenceSize: CGSize?
    let supportsBoundsPicker: Bool
    let showsTypePicker: Bool
    let regionReferenceOptions: [AutomationVisualReferenceOption]
    let imageReferenceOptions: [AutomationVisualReferenceOption]
    let baselineReferenceOptions: [AutomationVisualReferenceOption]
    @Binding var type: AutomationVisualConditionType
    @Binding var regionRef: String
    @Binding var searchRegionSpace: AutomationOCRSearchRegionSpace
    @Binding var hasRegion: Bool
    @Binding var regionX: Double
    @Binding var regionY: Double
    @Binding var regionWidth: Double
    @Binding var regionHeight: Double
    @Binding var imageRef: String
    @Binding var baselineRef: String
    @Binding var hasPixel: Bool
    @Binding var pixelX: Double
    @Binding var pixelY: Double
    @Binding var colorHex: String
    @Binding var hasThreshold: Bool
    @Binding var threshold: Double
    @Binding var requiresVisible: Bool
    let onDrawRegion: () -> Void
    let onClearRegion: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTypePicker {
                Picker(NSLocalizedString("Visual wait", comment: ""), selection: $type) {
                    ForEach(AutomationVisualConditionPresentation.allTypes, id: \.self) { type in
                        Label(
                            AutomationVisualConditionPresentation.title(for: type),
                            systemImage: AutomationVisualConditionPresentation.systemImage(for: type)
                        )
                        .tag(type)
                    }
                }
                .pickerStyle(.menu)
            }

            AutomationVisualReferenceFieldView(
                title: NSLocalizedString("Region reference", comment: ""),
                textFieldTitle: NSLocalizedString("Region reference", comment: ""),
                systemImage: "viewfinder.rectangular",
                emptyDetail: nil,
                options: regionReferenceOptions,
                reference: $regionRef
            )

            if supportsBoundsPicker {
                Picker(NSLocalizedString("Region space", comment: ""), selection: $searchRegionSpace) {
                    ForEach(AutomationOCRSearchRegionSpace.allCases, id: \.self) { space in
                        Text(space.titleForVisualCondition).tag(space)
                    }
                }
                .pickerStyle(.menu)

                AutomationVisualRegionBoundsEditorView(
                    spaceTitle: searchRegionSpace.titleForVisualCondition,
                    statusTitle: regionStatusTitle,
                    statusDetail: regionStatusDetail,
                    statusImage: regionStatusImage,
                    statusTint: regionStatusTint,
                    hasRegion: hasRegion,
                    isNormalizedSpace: searchRegionSpace.isNormalizedSpaceForVisualCondition,
                    referenceSize: referenceSize,
                    regionX: $regionX,
                    regionY: $regionY,
                    regionWidth: $regionWidth,
                    regionHeight: $regionHeight,
                    onDraw: onDrawRegion,
                    onClear: onClearRegion
                )
            }

            typeSpecificFields

            Toggle(NSLocalizedString("Require visible match", comment: ""), isOn: $requiresVisible)
                .toggleStyle(.switch)
        }
    }

    @ViewBuilder
    private var typeSpecificFields: some View {
        switch type {
        case .regionChanged:
            AutomationVisualReferenceFieldView(
                title: NSLocalizedString("Baseline reference", comment: ""),
                textFieldTitle: NSLocalizedString("Baseline reference", comment: ""),
                systemImage: "rectangle.dashed",
                emptyDetail: nil,
                options: baselineReferenceOptions,
                reference: $baselineRef
            )
            thresholdFields
        case .imageAppeared, .imageDisappeared:
            AutomationVisualReferenceFieldView(
                title: NSLocalizedString("Image reference", comment: ""),
                textFieldTitle: NSLocalizedString("Image reference", comment: ""),
                systemImage: "photo",
                emptyDetail: nil,
                options: imageReferenceOptions,
                reference: $imageRef
            )
            thresholdFields
        case .pixelMatched:
            AutomationVisualColorPickerView(colorHex: $colorHex)
            Toggle(NSLocalizedString("Use exact pixel", comment: ""), isOn: $hasPixel)
                .toggleStyle(.switch)
            if hasPixel {
                HStack(spacing: 8) {
                    numericField(NSLocalizedString("Pixel X", comment: ""), value: $pixelX, width: 74)
                    numericField(NSLocalizedString("Pixel Y", comment: ""), value: $pixelY, width: 74)
                }
            }
            thresholdFields
        }
    }

    private var thresholdFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(NSLocalizedString("Threshold", comment: ""), isOn: $hasThreshold)
                .toggleStyle(.switch)
            if hasThreshold {
                numericField(NSLocalizedString("Value", comment: ""), value: $threshold, width: 78)
            }
        }
    }

    private func numericField(_ label: String, value: Binding<Double>, width: CGFloat) -> some View {
        LabeledContent(label) {
            TextField(label, value: value, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
        .font(.caption)
    }
}

private struct AutomationVisualRegionBoundsEditorView: View {
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
                    Label(NSLocalizedString("Clear Bounds", comment: ""), systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(Brand.red500)
            }

            Button(action: onDraw) {
                Label(NSLocalizedString("Draw Bounds", comment: ""), systemImage: "viewfinder.rectangular")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
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
                        .fill(Brand.libraryBlue.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Brand.libraryBlue, lineWidth: 1.3)
                        )
                        .frame(width: previewRect.width, height: previewRect.height)
                        .offset(x: previewRect.minX, y: previewRect.minY)
                } else {
                    Label(NSLocalizedString("No bounds selected", comment: ""), systemImage: "viewfinder")
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
            Text(NSLocalizedString("Bounds", comment: ""))
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
            return NSLocalizedString("No bounds selected", comment: "")
        }

        return String(
            format: NSLocalizedString("%@ bounds: x %@, y %@, width %@, height %@", comment: ""),
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

extension AutomationOCRSearchRegionSpace {
    var titleForVisualCondition: String {
        switch self {
        case .automatic:
            return NSLocalizedString("Automatic", comment: "")
        case .displayAbsolute:
            return NSLocalizedString("Display absolute", comment: "")
        case .displayNormalized:
            return NSLocalizedString("Display normalized", comment: "")
        case .windowLocal:
            return NSLocalizedString("Window local", comment: "")
        case .windowNormalized:
            return NSLocalizedString("Window normalized", comment: "")
        case .contentLocal:
            return NSLocalizedString("Content local", comment: "")
        case .contentNormalized:
            return NSLocalizedString("Content normalized", comment: "")
        }
    }

    var isNormalizedSpaceForVisualCondition: Bool {
        switch self {
        case .displayNormalized, .windowNormalized, .contentNormalized:
            return true
        case .automatic, .displayAbsolute, .windowLocal, .contentLocal:
            return false
        }
    }
}
