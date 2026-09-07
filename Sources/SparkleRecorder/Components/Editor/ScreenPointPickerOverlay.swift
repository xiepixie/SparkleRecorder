import Cocoa
import SwiftUI

@MainActor
final class ScreenPointPickerOverlay {
    struct Configuration {
        var title: String
        var subtitle: String
        var systemImage: String
        var requiredClickCount: Int

        init(
            title: String,
            subtitle: String,
            systemImage: String = "scope",
            requiredClickCount: Int = 1
        ) {
            self.title = title
            self.subtitle = subtitle
            self.systemImage = systemImage
            self.requiredClickCount = max(1, requiredClickCount)
        }
    }

    var onPicked: ((CGPoint) -> Void)?
    var onCancelled: (() -> Void)?

    private var captureWindow: ScreenPointCaptureWindow?
    private var instructionPanel: NSPanel?
    private var activityToken: UUID?

    var isActive: Bool {
        captureWindow != nil || instructionPanel != nil
    }

    @discardableResult
    func start(configuration: Configuration) -> Bool {
        stop()
        guard let primaryScreen = NSScreen.screens.first else { return false }

        let unionFrame = NSScreen.screens.dropFirst().reduce(primaryScreen.frame) { partial, screen in
            partial.union(screen.frame)
        }
        let captureWindow = ScreenPointCaptureWindow(
            contentRect: unionFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        captureWindow.level = .screenSaver - 1
        captureWindow.isOpaque = false
        captureWindow.backgroundColor = NSColor.black.withAlphaComponent(0.001)
        captureWindow.hasShadow = false
        captureWindow.ignoresMouseEvents = false
        captureWindow.acceptsMouseMovedEvents = true
        captureWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let captureView = ScreenPointCaptureView(
            frame: NSRect(origin: .zero, size: unionFrame.size),
            requiredClickCount: configuration.requiredClickCount
        )
        captureView.autoresizingMask = [.width, .height]
        captureView.onPick = { [weak self] point in
            self?.stop()
            self?.onPicked?(point)
        }
        captureView.onCancel = { [weak self] in
            self?.stop()
            self?.onCancelled?()
        }
        captureWindow.contentView = captureView

        activityToken = AuxiliaryCaptureActivityCenter.shared.begin()
        self.captureWindow = captureWindow
        captureWindow.orderFrontRegardless()
        captureWindow.makeKey()
        captureWindow.makeFirstResponder(captureView)

        let panelWidth: CGFloat = 380
        let panelHeight: CGFloat = 72
        let panelFrame = NSRect(
            x: primaryScreen.frame.origin.x + (primaryScreen.frame.width - panelWidth) / 2,
            y: primaryScreen.frame.origin.y + primaryScreen.frame.height - panelHeight - 80,
            width: panelWidth,
            height: panelHeight
        )
        let panel = NSPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(
            rootView: PickerInstructionView(
                title: configuration.title,
                subtitle: configuration.subtitle,
                systemImage: configuration.systemImage
            )
        )

        self.instructionPanel = panel
        panel.orderFrontRegardless()
        return true
    }

    func stop() {
        captureWindow?.orderOut(nil)
        captureWindow = nil
        instructionPanel?.orderOut(nil)
        instructionPanel = nil
        AuxiliaryCaptureActivityCenter.shared.end(activityToken)
        activityToken = nil
    }

    func cancel() {
        guard isActive else { return }
        stop()
        onCancelled?()
    }
}

@MainActor
private final class ScreenPointCaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
private final class ScreenPointCaptureView: NSView {
    let requiredClickCount: Int
    var onPick: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?

    init(frame: NSRect, requiredClickCount: Int) {
        self.requiredClickCount = requiredClickCount
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount >= requiredClickCount else { return }
        let mouseLocation = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        onPick?(CGPoint(x: mouseLocation.x, y: primaryHeight - mouseLocation.y))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}
