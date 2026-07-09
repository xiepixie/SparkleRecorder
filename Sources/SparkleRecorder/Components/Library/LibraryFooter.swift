import Cocoa
import SwiftUI
import SparkleRecorderCore

struct LibraryFooter: View {
    let controller: MenuBarController
    @ObservedObject var state: AppState
    let isWindow: Bool
    @Binding var workspace: WorkspaceMode

    var body: some View {
        HStack(spacing: 6) {
            if workspace == .library {
                FooterRow(
                    icon: "plus",
                    label: String(localized: "New macro", table: "EditorUX"),
                    rightAccessory: AnyView(KeyCapView(text: "⌘R")),
                    action: { controller.toggleRecording() }
                )
                FooterRow(
                    icon: "plus.diamond",
                    label: String(localized: "New workflow", table: "Automation"),
                    rightAccessory: nil,
                    action: {
                        if isWindow {
                            workspace = .automation
                        } else {
                            controller.showAutomationWorkspace()
                        }
                    }
                )
            } else {
                FooterRow(
                    icon: "rectangle.stack",
                    label: String(localized: "Macro library", table: "EditorUX"),
                    rightAccessory: nil,
                    action: { workspace = .library }
                )
                FooterRow(
                    icon: "plus.diamond",
                    label: String(localized: "New workflow", table: "Automation"),
                    rightAccessory: nil,
                    action: { /* Currently placeholder */ }
                )
            }

            FooterRow(
                icon: "slider.horizontal.below.rectangle",
                label: String(localized: "Open editor", table: "EditorUX"),
                rightAccessory: nil,
                action: { controller.openEditor() }
            )
            FooterRow(
                icon: "gearshape",
                label: String(localized: "Settings", table: "Settings"),
                rightAccessory: AnyView(KeyCapView(text: "⌘,")),
                action: { controller.showSettingsWindow() }
            )
        }
    }
}
