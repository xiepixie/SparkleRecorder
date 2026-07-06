import SwiftUI
import SparkleRecorderCore

struct AutomationRuntimeStatusHairline: View {
    let status: AutomationDisplayStatus

    var body: some View {
        Capsule()
            .fill(status.tint.opacity(opacity))
            .frame(maxWidth: .infinity, minHeight: 2, maxHeight: 2)
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(true)
    }

    private var isVisible: Bool {
        switch status {
        case .scheduled, .cancelled:
            return false
        case .waiting, .queued, .running, .completed, .failed, .timedOut, .blocked:
            return true
        }
    }

    private var opacity: Double {
        switch status {
        case .running:
            return 0.85
        case .waiting, .queued:
            return 0.62
        case .failed, .timedOut, .blocked:
            return 0.78
        case .completed:
            return 0.5
        case .scheduled, .cancelled:
            return 0
        }
    }
}
