import SwiftUI

struct AutomationVisualReferenceFieldView: View {
    let title: String
    let textFieldTitle: String
    let systemImage: String
    let emptyDetail: String?
    let options: [AutomationVisualReferenceOption]
    @Binding var reference: String
    var onCapture: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !options.isEmpty {
                Picker(title, selection: pickerSelection) {
                    Text(NSLocalizedString("Custom", comment: ""))
                        .tag(Self.customSelection)

                    ForEach(options) { option in
                        Label(option.title, systemImage: systemImage)
                            .tag(option.key)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
                .accessibilityLabel(title)
            }

            HStack(spacing: 8) {
                if let onCapture {
                    Button(action: onCapture) {
                        Image(systemName: "camera.viewfinder")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.libraryBlue)
                    .help(NSLocalizedString("Capture new reference image", comment: ""))
                }

                TextField(textFieldTitle, text: normalizedReference)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .accessibilityLabel(title)

                if hasKnownReference {
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(Brand.libraryGreen)
                        .accessibilityLabel(NSLocalizedString("Known visual asset", comment: ""))
                } else if !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          !options.isEmpty {
                    Image(systemName: "questionmark.diamond")
                        .foregroundStyle(Brand.sigAmber)
                        .accessibilityLabel(NSLocalizedString("Custom visual asset reference", comment: ""))
                }
            }

            if let selectedDetail {
                Label(selectedDetail, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if options.isEmpty,
                      let emptyDetail,
                      !emptyDetail.isEmpty {
                Label(emptyDetail, systemImage: "text.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var pickerSelection: Binding<String> {
        Binding(
            get: {
                hasKnownReference ? reference.trimmingCharacters(in: .whitespacesAndNewlines) : Self.customSelection
            },
            set: { newValue in
                guard newValue != Self.customSelection else {
                    return
                }
                reference = newValue
            }
        )
    }

    private var normalizedReference: Binding<String> {
        Binding(
            get: { reference },
            set: { newValue in
                reference = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
    }

    private var selectedOption: AutomationVisualReferenceOption? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        return options.first { $0.key == trimmed }
    }

    private var hasKnownReference: Bool {
        selectedOption != nil
    }

    private var selectedDetail: String? {
        selectedOption?.subtitle
    }

    private static let customSelection = "__sparkle_custom_visual_reference__"
}
