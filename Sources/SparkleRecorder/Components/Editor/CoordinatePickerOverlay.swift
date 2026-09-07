import Cocoa

/// Coordinate-picking Adapter built on the shared screen-point picker Module.
@MainActor
final class CoordinatePickerOverlay {
    static let shared = CoordinatePickerOverlay()

    var onPicked: ((CGPoint) -> Void)?
    var onCancelled: (() -> Void)?

    private let picker = ScreenPointPickerOverlay()

    var isActive: Bool { picker.isActive }

    @discardableResult
    func start() -> Bool {
        picker.onPicked = { [weak self] point in
            self?.onPicked?(point)
        }
        picker.onCancelled = { [weak self] in
            self?.onCancelled?()
        }
        return picker.start(
            configuration: .init(
                title: String(localized: "Double-click anywhere to pick coordinate", table: "EditorUX"),
                subtitle: String(localized: "Press ESC to cancel", table: "Common"),
                systemImage: "scope",
                requiredClickCount: 2
            )
        )
    }

    func stop() {
        picker.stop()
    }

    func cancel() {
        picker.cancel()
    }
}
