import Cocoa
import SwiftUI
import SparkleRecorderCore

struct ActionRow: Identifiable {
    var id: UUID { group.id }
    let group: ActionGroup
}
