import Cocoa
import SwiftUI
import SparkleRecorderCore

struct LibraryFooter: View {
    let controller: MenuBarController
    @ObservedObject var state: AppState
    @Binding var workspace: WorkspaceMode

    var body: some View {
        HStack(spacing: 6) {
            if workspace == .library {
                FooterRow(
                    icon: "plus",
                    label: NSLocalizedString("New macro", comment: ""),
                    rightAccessory: AnyView(KeyCapView(text: "⌘R")),
                    action: { controller.toggleRecording() }
                )
                FooterRow(
                    icon: "plus.diamond",
                    label: NSLocalizedString("New workflow", comment: ""),
                    rightAccessory: nil,
                    action: { workspace = .automation }
                )
            } else {
                FooterRow(
                    icon: "rectangle.stack",
                    label: NSLocalizedString("Macro library", comment: ""),
                    rightAccessory: nil,
                    action: { workspace = .library }
                )
                FooterRow(
                    icon: "plus.diamond",
                    label: NSLocalizedString("New workflow", comment: ""),
                    rightAccessory: nil,
                    action: { /* Currently placeholder */ }
                )
            }

            FooterRow(
                icon: "slider.horizontal.below.rectangle",
                label: NSLocalizedString("Open editor", comment: ""),
                rightAccessory: nil,
                action: { controller.openEditor() }
            )
            FooterRow(
                icon: "gearshape",
                label: NSLocalizedString("Settings", comment: ""),
                rightAccessory: AnyView(KeyCapView(text: "⌘,")),
                action: { controller.showSettingsWindow() }
            )
        }
    }
}
