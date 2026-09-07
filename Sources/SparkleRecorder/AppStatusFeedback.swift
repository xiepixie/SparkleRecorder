import Foundation

/// A user-facing outcome or in-progress state shown on the app's compact status surface.
/// Business modules provide the message and semantic tone; presentation owns the icon,
/// layout, animation, and dismissal behavior.
struct AppStatusFeedback: Equatable, Identifiable, Sendable {
    enum Tone: Equatable, Sendable {
        case info
        case success
        case warning
        case error
        case progress

        var defaultDismissAfter: TimeInterval? {
            switch self {
            case .success:
                return 4
            case .info:
                return 5
            case .warning:
                return 7
            case .error, .progress:
                return nil
            }
        }
    }

    let id: UUID
    var message: String
    var tone: Tone
    var dismissAfter: TimeInterval?

    init(
        id: UUID = UUID(),
        message: String,
        tone: Tone = .info,
        dismissAfter: TimeInterval? = nil
    ) {
        self.id = id
        self.message = message
        self.tone = tone
        self.dismissAfter = dismissAfter ?? tone.defaultDismissAfter
    }
}
