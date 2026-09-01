import SwiftUI
import SparkleRecorderCore

extension AutomationWorkflowActivationProjection.State {
    var systemImage: String {
        switch self {
        case .blocked: "exclamationmark.octagon"
        case .manualOnly: "hand.tap"
        case .scheduled: "calendar.badge.checkmark"
        case .running: "play.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .blocked: .red
        case .manualOnly: .orange
        case .scheduled: .green
        case .running: Brand.libraryBlue
        }
    }
}

extension AutomationWorkflowActivationProjection.CheckSeverity {
    var systemImage: String {
        switch self {
        case .blocking: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .ready: "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .blocking: .red
        case .warning: .orange
        case .ready: .green
        }
    }
}
