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
        Button(NSLocalizedString("Choose Package", comment: ""), systemImage: "folder", action: onChoosePackage)
            .buttonStyle(.bordered)
            .disabled(!hasSourceDirectory)
            .help(NSLocalizedString("Register an image that is already inside this draft package.", comment: ""))
    }

    private var importFileButton: some View {
        Button(
            NSLocalizedString("Import File", comment: ""),
            systemImage: "square.and.arrow.down",
            action: onImportExternalAsset
        )
        .buttonStyle(.bordered)
        .disabled(!hasSourceDirectory || isImportingAsset)
        .help(NSLocalizedString("Copy an external image into this draft package and register it.", comment: ""))
    }

    private var captureBaselineButton: some View {
        Button(
            NSLocalizedString("Capture Baseline", comment: ""),
            systemImage: "viewfinder.rectangular",
            action: onCaptureBaseline
        )
        .buttonStyle(.bordered)
        .disabled(!hasSourceDirectory || isCapturingBaseline)
    }

    private var registerAssetButton: some View {
        Button(NSLocalizedString("Register Asset", comment: ""), systemImage: "plus", action: onRegisterAsset)
            .buttonStyle(.bordered)
            .disabled(!canRegister)
    }
}
