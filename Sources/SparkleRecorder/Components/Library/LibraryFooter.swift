import Cocoa
import SwiftUI
import SparkleRecorderCore

struct LibraryFooter: View {
    let controller: MenuBarController
    @ObservedObject var state: AppState

	    var body: some View {
	        HStack(spacing: 6) {
	            FooterRow(
	                icon: "plus",
	                label: NSLocalizedString("New macro", comment: ""),
                rightAccessory: AnyView(KeyCapView(text: "⌘R")),
                action: { controller.toggleRecording() }
            )
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
