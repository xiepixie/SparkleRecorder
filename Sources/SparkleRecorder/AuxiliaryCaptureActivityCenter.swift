import Combine
import Foundation

/// Tracks screen-picking sessions that temporarily own foreground pointer/capture input.
/// Pickers acquire a token before async preparation begins and release it only after
/// their windows/tasks are gone, so recording, playback, Automation, and app editing
/// all observe the same ownership state.
@MainActor
final class AuxiliaryCaptureActivityCenter: ObservableObject {
    static let shared = AuxiliaryCaptureActivityCenter()

    @Published private(set) var isActive = false

    private var tokens: Set<UUID> = []

    @discardableResult
    func begin() -> UUID {
        let token = UUID()
        tokens.insert(token)
        updatePublishedState()
        return token
    }

    func end(_ token: UUID?) {
        guard let token else { return }
        tokens.remove(token)
        updatePublishedState()
    }

    private func updatePublishedState() {
        let active = !tokens.isEmpty
        if isActive != active {
            isActive = active
        }
    }
}
