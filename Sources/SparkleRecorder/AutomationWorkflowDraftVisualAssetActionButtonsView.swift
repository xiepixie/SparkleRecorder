import SwiftUI

struct AutomationWorkflowDraftVisualAssetActionButtonsView: View {
    let hasSourceDirectory: Bool
    let isImportingAsset: Bool
    let isCapturingBaseline: Bool
    let canRegister: Bool
    let onChoosePackage: () -> Void
    let onImportExternalAsset: () -> Void
    let onCaptureBaseline: () -> Void
    let onRegisterAsset: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                choosePackageButton
                importFileButton
                captureBaselineButton
                registerAssetButton
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    choosePackageButton
                    importFileButton
                }
                HStack(spacing: 8) {
                    captureBaselineButton
                    registerAssetButton
                }
            }
        }
    }

    private var choosePackageButton: some View {
        Button(String(localized: "Choose Package", table: "Common"), systemImage: "folder", action: onChoosePackage)
            .buttonStyle(.bordered)
            .disabled(!hasSourceDirectory)
            .help(String(localized: "Register an image that is already inside this draft package.", table: "Common"))
    }

    private var importFileButton: some View {
        Button(
            String(localized: "Import File", table: "Common"),
            systemImage: "square.and.arrow.down",
            action: onImportExternalAsset
        )
        .buttonStyle(.bordered)
        .disabled(!hasSourceDirectory || isImportingAsset)
        .help(String(localized: "Copy an external image into this draft package and register it.", table: "Common"))
    }

    private var captureBaselineButton: some View {
        Button(
            String(localized: "Capture Baseline", table: "Common"),
            systemImage: "viewfinder.rectangular",
            action: onCaptureBaseline
        )
        .buttonStyle(.bordered)
        .disabled(!hasSourceDirectory || isCapturingBaseline)
    }

    private var registerAssetButton: some View {
        Button(String(localized: "Register Asset", table: "Common"), systemImage: "plus", action: onRegisterAsset)
            .buttonStyle(.bordered)
            .disabled(!canRegister)
    }
}
