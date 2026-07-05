import Cocoa
import SwiftUI
import SparkleRecorderCore

struct EditorToolbar: View {
    let macro: SavedMacro?
    let rowCount: Int
    let duration: TimeInterval
    @Binding var hideMouseMoves: Bool
    @Binding var showAllPaths: Bool
    @Binding var showOverlayPreview: Bool
    @Binding var smartMergeGestures: Bool
    let onExport: () -> Void

	    var body: some View {
	        VStack(spacing: 0) {
	            HStack(spacing: 14) {
	                BrandMark(size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(macro?.name ?? NSLocalizedString("Untitled macro", comment: ""))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Label(String(format: NSLocalizedString("%d events", comment: ""), rowCount), systemImage: "wave.3.right")
                        Text("·").foregroundStyle(.tertiary)
                        Label(formatDuration(duration), systemImage: "clock")
                        if let m = macro {
                            Text("·").foregroundStyle(.tertiary)
                            Text(String(format: NSLocalizedString("edited %@", comment: ""), RelativeTime.string(from: m.modifiedAt)))
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                }

                Spacer()

	                HStack(spacing: 6) {
	                    EditorToolbarToggle(
	                        isOn: $showOverlayPreview,
	                        title: NSLocalizedString("Preview", comment: ""),
	                        help: NSLocalizedString("Show or hide the on-screen coordinate preview overlay", comment: ""),
	                        icon: "eye",
	                        tint: Brand.sigTeal
	                    )
	                    EditorToolbarToggle(
	                        isOn: $showAllPaths,
	                        title: NSLocalizedString("Paths", comment: ""),
	                        help: NSLocalizedString("Show paths for all actions instead of only the selection", comment: ""),
	                        icon: "point.topleft.down.to.point.bottomright.curvepath",
	                        tint: Brand.sigViolet
	                    )
	                    EditorToolbarToggle(
	                        isOn: $hideMouseMoves,
	                        title: NSLocalizedString("Moves", comment: ""),
	                        help: NSLocalizedString("Hide raw mouse-move rows in the action list", comment: ""),
	                        icon: "eye.slash.fill",
	                        tint: Brand.sigAmber
	                    )
	                    EditorToolbarToggle(
	                        isOn: $smartMergeGestures,
	                        title: NSLocalizedString("Merge", comment: ""),
	                        help: NSLocalizedString("Merge raw events into editable semantic actions", comment: ""),
	                        icon: "arrow.triangle.merge",
	                        tint: Brand.libraryGreen
	                    )
	                }
	                .padding(.horizontal, 8)
	
	                // Export
	                EditorExportButton(action: onExport)

            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Divider()
	        }
	        .background(VisualEffectBackground(material: .titlebar, blendingMode: .withinWindow))
	    }
}
