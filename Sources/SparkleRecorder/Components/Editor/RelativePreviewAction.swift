import Cocoa
import SwiftUI
import SparkleRecorderCore

struct RelativePreviewAction: Identifiable {
    let id: UUID
    let kind: ActionGroupKind
    let selectedPoint: CGPoint?
    let dragPath: [CGPoint]
    let observedFrame: CGRect?
    let searchRegion: CGRect?
    let fallbackPoint: CGPoint?
    let themeColor: Color
    let order: Int
}
