import SwiftUI
import SparkleRecorderCore

extension AutomationDisplayStatus {
    var systemImage: String {
        switch self {
        case .scheduled:
            "calendar.badge.clock"
        case .waiting:
            "hourglass"
        case .queued:
            "text.line.first.and.arrowtriangle.forward"
        case .running:
            "play.circle.fill"
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "xmark.octagon.fill"
        case .cancelled:
            "stop.circle.fill"
        case .timedOut:
            "timer"
        case .blocked:
            "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .scheduled:
            Brand.libraryBlue
        case .waiting:
            Brand.sigAmber
        case .queued:
            Brand.sigTeal
        case .running:
            Brand.sigGreen
        case .completed:
            Brand.libraryGreen
        case .failed:
            Brand.red500
        case .cancelled:
            .secondary
        case .timedOut:
            Brand.sigViolet
        case .blocked:
            Brand.sigAmber
        }
    }
}

extension AutomationDependencyDisplayStatus {
    var tint: Color {
        switch self {
        case .pending:
            .secondary
        case .waiting:
            Brand.sigAmber
        case .satisfied:
            Brand.libraryGreen
        case .blocked:
            Brand.red500
        case .disabled:
            Color.secondary.opacity(0.45)
        }
    }

    var dashPattern: [CGFloat] {
        switch self {
        case .pending, .waiting:
            [6, 5]
        case .disabled:
            [2, 4]
        case .satisfied, .blocked:
            []
        }
    }
}

extension AutomationResourceTimelineLane {
    var tint: Color {
        switch self {
        case .foregroundInput:
            Brand.red500
        case .screenCapture:
            Brand.sigTeal
        case .waiting:
            Brand.sigAmber
        case .completed:
            Brand.libraryGreen
        }
    }
}
