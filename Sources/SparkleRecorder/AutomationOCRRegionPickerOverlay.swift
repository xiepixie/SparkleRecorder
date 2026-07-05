import Cocoa
import SwiftUI
import SparkleRecorderCore

@MainActor
private final class OCRRegionCaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
private final class OCRRegionCaptureView: NSView {
    var onPicked: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startLocalPoint: CGPoint?
    private var currentLocalPoint: CGPoint?
    private var startScreenPoint: CGPoint?
    private var currentScreenPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func becomeFirstResponder() -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        startLocalPoint = convert(event.locationInWindow, from: nil)
        currentLocalPoint = startLocalPoint
        startScreenPoint = Self.cgScreenPoint()
        currentScreenPoint = startScreenPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentLocalPoint = convert(event.locationInWindow, from: nil)
        currentScreenPoint = Self.cgScreenPoint()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentLocalPoint = convert(event.locationInWindow, from: nil)
        currentScreenPoint = Self.cgScreenPoint()
        needsDisplay = true

        guard let startScreenPoint,
              let currentScreenPoint else {
            onCancel?()
            return
        }

        let selectedRect = Self.standardRect(from: startScreenPoint, to: currentScreenPoint)
        guard selectedRect.width >= 8, selectedRect.height >= 8 else {
            onCancel?()
            return
        }

        onPicked?(selectedRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.18).setFill()
        dirtyRect.fill()

        guard let startLocalPoint,
              let currentLocalPoint else {
            return
        }

        let rect = Self.standardRect(from: startLocalPoint, to: currentLocalPoint)
        NSColor.clear.setFill()
        rect.fill(using: .clear)

        let fillPath = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        NSColor.systemOrange.withAlphaComponent(0.18).setFill()
        fillPath.fill()

        let strokePath = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        strokePath.lineWidth = 2
        NSColor.systemOrange.setStroke()
        strokePath.stroke()
    }

    private static func cgScreenPoint() -> CGPoint {
        let mouseLocation = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(
            x: mouseLocation.x,
            y: primaryHeight - mouseLocation.y
        )
    }

    private static func standardRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}

private struct OCRRegionPickerInstructionView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "viewfinder.rectangular")
                .font(.headline)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Drag to select OCR region", comment: ""))
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.white)
                Text(NSLocalizedString("Press ESC to cancel", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 8)
    }
}

@MainActor
final class AutomationOCRRegionPickerOverlay {
    static let shared = AutomationOCRRegionPickerOverlay()

    private var captureWindow: OCRRegionCaptureWindow?
    private var instructionPanel: NSPanel?

    var onPicked: ((AutomationOCRSearchRegionSelection) -> Void)?
    var onCancelled: (() -> Void)?

    func start() {
        stop()

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            onCancelled?()
            return
        }

        let win = OCRRegionCaptureWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.level = .screenSaver - 1
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = false
        win.acceptsMouseMovedEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let captureView = OCRRegionCaptureView(frame: NSRect(origin: .zero, size: screen.frame.size))
        captureView.autoresizingMask = [.width, .height]
        captureView.onPicked = { [weak self, weak screen] selectedRect in
            guard let self,
                  let screen,
                  let selection = Self.selection(from: selectedRect, on: screen) else {
                self?.stop()
                self?.onCancelled?()
                return
            }
            self.stop()
            self.onPicked?(selection)
        }
        captureView.onCancel = { [weak self] in
            self?.stop()
            self?.onCancelled?()
        }
        win.contentView = captureView

        captureWindow = win
        win.orderFrontRegardless()
        win.makeKey()
        win.makeFirstResponder(captureView)
        showInstructionPanel(on: screen)
    }

    func stop() {
        captureWindow?.orderOut(nil)
        captureWindow = nil
        instructionPanel?.orderOut(nil)
        instructionPanel = nil
    }

    private func showInstructionPanel(on screen: NSScreen) {
        let panelWidth: CGFloat = 320
        let panelHeight: CGFloat = 64
        let panelFrame = NSRect(
            x: screen.frame.origin.x + (screen.frame.width - panelWidth) / 2,
            y: screen.frame.origin.y + screen.frame.height - panelHeight - 80,
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

        let host = NSHostingView(rootView: OCRRegionPickerInstructionView())
        host.frame = NSRect(origin: .zero, size: panelFrame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        instructionPanel = panel
        panel.orderFrontRegardless()
    }

    private static func selection(
        from globalTopLeftRect: CGRect,
        on screen: NSScreen
    ) -> AutomationOCRSearchRegionSelection? {
        let screenFrame = topLeftFrame(for: screen)
        let selectedPointRect = globalTopLeftRect.intersection(screenFrame)
        guard !selectedPointRect.isNull,
              selectedPointRect.width > 1,
              selectedPointRect.height > 1 else {
            return nil
        }

        let scale = screen.backingScaleFactor
        let displayBounds = RectValue(
            x: 0,
            y: 0,
            width: screenFrame.width * scale,
            height: screenFrame.height * scale
        )
        let selectedDisplayRegion = RectValue(
            x: (selectedPointRect.minX - screenFrame.minX) * scale,
            y: (selectedPointRect.minY - screenFrame.minY) * scale,
            width: selectedPointRect.width * scale,
            height: selectedPointRect.height * scale
        )

        let center = CGPoint(x: globalTopLeftRect.midX, y: globalTopLeftRect.midY)
        let frames = windowFrames(containing: center, on: screen)

        return AutomationOCRSearchRegionSelection(
            displayBounds: displayBounds,
            selectedDisplayRegion: selectedDisplayRegion,
            windowFrame: frames.windowFrame,
            contentFrame: frames.contentFrame
        )
    }

    private static func windowFrames(
        containing point: CGPoint,
        on screen: NSScreen
    ) -> (windowFrame: RectValue?, contentFrame: RectValue?) {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return (nil, nil)
        }

        let currentPID = getpid()
        for windowInfo in windowInfoList {
            guard let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  pid != currentPID else {
                continue
            }

            let layer = windowInfo[kCGWindowLayer as String] as? Int32 ?? 0
            guard layer == 0 else { continue }

            guard let frame = windowFrame(from: windowInfo),
                  frame.contains(point) else {
                continue
            }

            let content = CoordinateMapper.resolveContentFrame(
                for: pid,
                outerFrame: RectValue(
                    x: frame.minX,
                    y: frame.minY,
                    width: frame.width,
                    height: frame.height
                )
            ).frame

            return (
                displayRect(from: frame, on: screen),
                displayRect(from: content, on: screen)
            )
        }

        return (nil, nil)
    }

    private static func windowFrame(from windowInfo: [String: Any]) -> CGRect? {
        guard let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
              let x = cgFloat(bounds["X"]),
              let y = cgFloat(bounds["Y"]),
              let width = cgFloat(bounds["Width"]),
              let height = cgFloat(bounds["Height"]),
              width > 1,
              height > 1 else {
            return nil
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func displayRect(from rect: CGRect, on screen: NSScreen) -> RectValue? {
        let screenFrame = topLeftFrame(for: screen)
        let clipped = rect.intersection(screenFrame)
        guard !clipped.isNull,
              clipped.width > 1,
              clipped.height > 1 else {
            return nil
        }

        let scale = screen.backingScaleFactor
        return RectValue(
            x: (clipped.minX - screenFrame.minX) * scale,
            y: (clipped.minY - screenFrame.minY) * scale,
            width: clipped.width * scale,
            height: clipped.height * scale
        )
    }

    private static func topLeftFrame(for screen: NSScreen) -> CGRect {
        guard let primaryScreen = NSScreen.screens.first else {
            return screen.frame
        }
        let primaryHeight = primaryScreen.frame.height
        return CGRect(
            x: screen.frame.minX,
            y: primaryHeight - (screen.frame.minY + screen.frame.height),
            width: screen.frame.width,
            height: screen.frame.height
        )
    }

    private static func cgFloat(_ value: Any?) -> CGFloat? {
        if let value = value as? CGFloat {
            return value
        }
        if let value = value as? NSNumber {
            return CGFloat(truncating: value)
        }
        return nil
    }
}
