import AppKit

@MainActor
struct ApplicationWindowVisibilitySnapshot {
    private let appWasHidden: Bool
    private let appWasActive: Bool
    private let visibleWindows: [NSWindow]
    private let keyWindow: NSWindow?

    static func capture() -> ApplicationWindowVisibilitySnapshot {
        ApplicationWindowVisibilitySnapshot(
            appWasHidden: NSApp.isHidden,
            appWasActive: NSApp.isActive,
            visibleWindows: NSApp.windows.filter(\.isVisible),
            keyWindow: NSApp.keyWindow
        )
    }

    func concealCapturedWindows() {
        for window in visibleWindows where window.isVisible {
            window.orderOut(nil)
        }
    }

    func restore() {
        guard !appWasHidden else { return }

        NSApp.unhide(nil)
        for window in visibleWindows where !window.isVisible {
            window.orderFront(nil)
        }

        guard appWasActive else { return }
        NSApp.activate(ignoringOtherApps: true)
        if let keyWindow, visibleWindows.contains(where: { $0 === keyWindow }) {
            keyWindow.makeKeyAndOrderFront(nil)
        }
    }
}
