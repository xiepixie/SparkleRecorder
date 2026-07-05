import Cocoa
import SwiftUI

private final class CaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Full-screen transparent NSView that directly captures mouse and keyboard events.
/// This replaces NSEvent.addGlobalMonitorForEvents which requires the separate
/// "Input Monitoring" permission (distinct from Accessibility on macOS 10.15+).
/// By using a real window that accepts events, we avoid the permission issue entirely.
private final class PickerCaptureView: NSView {
    var onDoubleClick: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }
    
    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            let mouseLoc = NSEvent.mouseLocation
            let screenHeight = NSScreen.screens.first?.frame.height ?? 0
            let cgPt = CGPoint(x: mouseLoc.x, y: screenHeight - mouseLoc.y)
            onDoubleClick?(cgPt)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onCancel?()
        }
    }
    
    // Show crosshair cursor while picking
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}

final class CoordinatePickerOverlay {
    static let shared = CoordinatePickerOverlay()
    
    private var captureWindow: CaptureWindow?
    private var instructionPanel: NSPanel?
    
    var onPicked: ((CGPoint) -> Void)?
    var onCancelled: (() -> Void)?
    
    func start() {
        // Clean up any existing windows first to avoid leaks
        stop()
        
        guard let mainScreen = NSScreen.screens.first else { return }
        let screenFrame = mainScreen.frame
        let unionFrame = NSScreen.screens.dropFirst().reduce(mainScreen.frame) { rect, screen in
            rect.union(screen.frame)
        }
        
        // 1. Create the full-screen transparent click-capture window.
        //    This window directly receives all mouse and keyboard events —
        //    no Input Monitoring permission required.
        let win = CaptureWindow(
            contentRect: unionFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.level = .screenSaver - 1  // Below instruction panel, above everything else
        win.isOpaque = false
        win.backgroundColor = NSColor.black.withAlphaComponent(0.001) // Nearly invisible but accepts events
        win.hasShadow = false
        win.ignoresMouseEvents = false
        win.acceptsMouseMovedEvents = true
        // Ensure window can receive key events without full activation
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        
        let captureView = PickerCaptureView(frame: NSRect(origin: .zero, size: unionFrame.size))
        captureView.autoresizingMask = [.width, .height]
        captureView.onDoubleClick = { [weak self] cgPt in
            self?.stop()
            self?.onPicked?(cgPt)
        }
        captureView.onCancel = { [weak self] in
            self?.stop()
            self?.onCancelled?()
        }
        win.contentView = captureView
        
        self.captureWindow = win
        win.orderFrontRegardless()
        win.makeKey()
        // Ensure the capture view is first responder so it receives keyDown
        win.makeFirstResponder(captureView)
        
        // 2. Create the instruction panel (floats above the capture window)
        let panelWidth: CGFloat = 340
        let panelHeight: CGFloat = 64
        let panelFrame = NSRect(
            x: screenFrame.origin.x + (screenFrame.width - panelWidth) / 2,
            y: screenFrame.origin.y + screenFrame.height - panelHeight - 80,
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
        
        let host = NSHostingView(rootView: PickerInstructionView())
        host.frame = NSRect(origin: .zero, size: panelFrame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        
        self.instructionPanel = panel
        panel.orderFrontRegardless()
    }
    
    func stop() {
        captureWindow?.orderOut(nil)
        captureWindow = nil
        instructionPanel?.orderOut(nil)
        instructionPanel = nil
    }
}
