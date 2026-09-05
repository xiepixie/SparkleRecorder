import Cocoa
import SparkleRecorderCore
import SwiftUI

struct LibraryFooter: View {
  let controller: MenuBarController
  @ObservedObject var state: AppState
  let isWindow: Bool
  @Binding var workspace: WorkspaceMode

  var body: some View {
    HStack(spacing: 6) {
      FooterRow(
        icon: "rectangle.stack",
        label: String(localized: "Macro library", table: "EditorUX"),
        rightAccessory: nil,
        action: { workspace = .library }
      )
      FooterRow(
        icon: "bolt.horizontal.circle",
        label: String(localized: "Automations", table: "Automation"),
        rightAccessory: nil,
        action: {
          if isWindow {
            workspace = .automation
          } else {
            controller.showAutomationWorkspace()
          }
        }
      )

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
