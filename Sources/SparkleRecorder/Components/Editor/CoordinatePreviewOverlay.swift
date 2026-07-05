import Cocoa
import SwiftUI

/// A borderless overlay panel that lets clicks pass through to apps below
/// EXCEPT when the mouse is over an interactive crosshair / drag-handle.
/// Uses a polling timer on NSEvent.mouseLocation to toggle ignoresMouseEvents,
/// which is the standard macOS pattern for click-through overlays.
@MainActor
class ClickThroughPanel: NSPanel {
    /// Returns true if the given CG-screen point is over an interactive element.
    var isPointInteractive: ((_ cgScreenPoint: CGPoint) -> Bool)?
    /// Called when the user presses ESC to dismiss the overlay.
    var onClose: (() -> Void)?
    
    private var trackingTimer: Timer?
    private var isDragging = false
    private var escMonitor: Any?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Start the mouse-position polling loop.
    func startTracking() {
        self.ignoresMouseEvents = true // Default: everything passes through
        
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, !self.isDragging else { return }
                let cocoaPt = NSEvent.mouseLocation
                let screenH = NSScreen.screens.first?.frame.height ?? 0
                let cgPt = CGPoint(x: cocoaPt.x, y: screenH - cocoaPt.y)
                let interactive = self.isPointInteractive?(cgPt) ?? false
                // Only update when the value actually changes to avoid flickering
                if self.ignoresMouseEvents == interactive {
                    self.ignoresMouseEvents = !interactive
                }
            }
        }
        
        // ESC key listener (local — works when SparkleRecorder is active)
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.stopTracking()
                self?.onClose?()
                return nil
            }
            return event
        }
    }
    
    /// Stop polling and clean up monitors.
    func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        isDragging = false
        self.ignoresMouseEvents = true
        if let mon = escMonitor {
            NSEvent.removeMonitor(mon)
            escMonitor = nil
        }
    }
    
    override func sendEvent(_ event: NSEvent) {
        // Track drag state so the timer doesn't toggle ignoresMouseEvents mid-drag
        switch event.type {
        case .leftMouseDown:
            isDragging = true
        case .leftMouseUp:
            isDragging = false
        default:
            break
        }
        super.sendEvent(event)
    }
    
    deinit {
        MainActor.assumeIsolated {
            stopTracking()
        }
    }
}

@MainActor
class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        // Prevent NSHostingView from shrinking to SwiftUI intrinsic content size
        self.sizingOptions = []
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    
    /// Ensure the hosting view is NOT opaque so the transparent window works.
    override var isOpaque: Bool { false }
    
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Ensure all layers are transparent and non-clipping
        guard let layer = self.layer else { return }
        configureTransparency(on: layer)
    }
    
    override func layout() {
        super.layout()
        if let layer = self.layer {
            configureTransparency(on: layer)
        }
    }
    
    func configureTransparency(on layer: CALayer) {
        layer.isOpaque = false
        layer.backgroundColor = .clear
        layer.masksToBounds = false
        if let subs = layer.sublayers {
            for sub in subs {
                configureTransparency(on: sub)
            }
        }
    }
}

@MainActor
func screenToSwiftUI(_ pt: CGPoint, window: NSWindow, primaryScreenHeight: CGFloat) -> CGPoint {
    let cocoaScreenPt = NSPoint(x: pt.x, y: primaryScreenHeight - pt.y)
    let localPt = window.convertPoint(fromScreen: cocoaScreenPt)
    return CGPoint(
        x: localPt.x,
        y: (window.contentView?.bounds.height ?? window.frame.height) - localPt.y
    )
}

@MainActor
func screenToSwiftUI(_ rect: CGRect, window: NSWindow, primaryScreenHeight: CGFloat) -> CGRect {
    let topLeft = screenToSwiftUI(CGPoint(x: rect.minX, y: rect.minY), window: window, primaryScreenHeight: primaryScreenHeight)
    let bottomRight = screenToSwiftUI(CGPoint(x: rect.maxX, y: rect.maxY), window: window, primaryScreenHeight: primaryScreenHeight)
    return CGRect(
        x: min(topLeft.x, bottomRight.x),
        y: min(topLeft.y, bottomRight.y),
        width: abs(bottomRight.x - topLeft.x),
        height: abs(bottomRight.y - topLeft.y)
    )
}

@MainActor
func swiftuiToScreen(_ pt: CGPoint, window: NSWindow, primaryScreenHeight: CGFloat) -> CGPoint {
    let localPt = NSPoint(
        x: pt.x,
        y: (window.contentView?.bounds.height ?? window.frame.height) - pt.y
    )
    let cocoaScreenPt = window.convertPoint(toScreen: localPt)
    return CGPoint(
        x: cocoaScreenPt.x,
        y: primaryScreenHeight - cocoaScreenPt.y
    )
}

@MainActor
final class OverlayState: ObservableObject {
    @Published var actions: [RelativePreviewAction] = []
    @Published var selectedActionID: UUID? = nil
    weak var window: NSWindow?
    var primaryScreenHeight: CGFloat = 0
}

@MainActor
final class CoordinatePreviewOverlay {
    static let shared = CoordinatePreviewOverlay()
    
    let state = OverlayState()
    private var window: NSWindow?
    
    var onDragStarted: ((UUID) -> Void)?
    var onDragStartPointEnded: ((UUID, CGFloat, CGFloat) -> Void)?
    var onDragEndPointEnded: ((UUID, CGFloat, CGFloat) -> Void)?
    var onDragPathEnded: ((UUID, CGFloat, CGFloat) -> Void)?
    var onDragPathPointEnded: ((UUID, Int, CGFloat, CGFloat) -> Void)?
    
    func clearCallbacks() {
        onDragStarted = nil
        onDragStartPointEnded = nil
        onDragEndPointEnded = nil
        onDragPathEnded = nil
        onDragPathPointEnded = nil
    }
    
    func show(actions: [PreviewAction], selectedActionID: UUID? = nil) {
        guard let primaryScreen = NSScreen.screens.first else { return }
        let primaryScreenHeight = primaryScreen.frame.height
        
        let unionFrame = NSScreen.screens.dropFirst().reduce(primaryScreen.frame) { rect, screen in
            rect.union(screen.frame)
        }
        
        if window == nil {
            let win = ClickThroughPanel(
                contentRect: unionFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            win.level = .statusBar
            win.isOpaque = false
            win.backgroundColor = .clear
            win.ignoresMouseEvents = false
            win.hasShadow = false
            win.hidesOnDeactivate = false
            win.acceptsMouseMovedEvents = true
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            
            // Tell the panel how to decide if a click is "interactive"
            win.isPointInteractive = { [weak self] cgScreenPoint in
                guard let self = self, let win = self.window else { return false }
                let screenH = NSScreen.screens.first?.frame.height ?? 0
                let actions = self.state.actions
                // Convert CG screen point → SwiftUI local coordinates
                let cocoaPt = NSPoint(x: cgScreenPoint.x, y: screenH - cgScreenPoint.y)
                let localPt = win.convertPoint(fromScreen: cocoaPt)
                let viewH = win.contentView?.bounds.height ?? win.frame.height
                let sx = localPt.x
                let sy = viewH - localPt.y
                
                for action in actions {
                    if let pt = action.selectedPoint {
                        let dx = sx - pt.x, dy = sy - pt.y
                        if dx * dx + dy * dy <= 784 { return true } // 28^2
                    }
                    if action.kind.canPreviewPath,
                       action.dragPath.count > 1 {
                        if action.kind.previewsPointSequence {
                            for point in action.dragPath {
                                let dx = sx - point.x, dy = sy - point.y
                                if dx * dx + dy * dy <= 784 { return true }
                            }
                        } else if let endPt = action.dragPath.last {
                            let dx = sx - endPt.x, dy = sy - endPt.y
                            if dx * dx + dy * dy <= 784 { return true }
                        }
                        if distanceFromPoint(CGPoint(x: sx, y: sy), toPolyline: action.dragPath) <= 10 {
                            return true
                        }
                    }
                }
                return false
            }
            
            let host = ClickThroughHostingView(rootView: TargetCrosshairView(state: self.state))
            host.frame = NSRect(origin: .zero, size: unionFrame.size)
            host.autoresizingMask = [.width, .height]
            win.contentView = host
            self.window = win
            
            // Start the mouse-position polling for click-through
            win.startTracking()
        } else {
            window?.setFrame(unionFrame, display: true)
        }
        
        guard let win = self.window else { return }
        self.state.window = win
        self.state.primaryScreenHeight = primaryScreenHeight
        
        let relativeActions = actions.map { action -> RelativePreviewAction in
            let mappedStart = action.selectedPoint.map { screenToSwiftUI($0, window: win, primaryScreenHeight: primaryScreenHeight) }
            let mappedPath = action.dragPath.map { screenToSwiftUI($0, window: win, primaryScreenHeight: primaryScreenHeight) }
	            return RelativePreviewAction(
	                id: action.id,
	                kind: action.kind,
	                selectedPoint: mappedStart,
	                dragPath: mappedPath,
	                observedFrame: action.observedFrame.map { screenToSwiftUI($0, window: win, primaryScreenHeight: primaryScreenHeight) },
	                searchRegion: action.searchRegion.map { screenToSwiftUI($0, window: win, primaryScreenHeight: primaryScreenHeight) },
	                fallbackPoint: action.fallbackPoint.map { screenToSwiftUI($0, window: win, primaryScreenHeight: primaryScreenHeight) },
	                themeColor: action.themeColor,
	                order: action.order
	            )
        }
        
        self.state.actions = relativeActions
        self.state.selectedActionID = selectedActionID
        
        if let win = window, !win.isVisible {
            win.orderFrontRegardless()
        }
    }
    
    func hide() {
        (window as? ClickThroughPanel)?.stopTracking()
        window?.orderOut(nil)
        window = nil
    }
    
    func setIgnoresMouseEvents(_ ignore: Bool) {
        window?.ignoresMouseEvents = ignore
    }
}

extension CGSize {
    func clamped(to maxVal: CGFloat) -> CGSize {
        CGSize(
            width: max(min(width, maxVal), -maxVal),
            height: max(min(height, maxVal), -maxVal)
        )
    }
}

struct ActiveDragEdit {
    var actionID: UUID
    var handle: DragHandle
    var translation: CGSize
    
    var clampedTranslation: CGSize {
        translation.clamped(to: 800)
    }
}

enum DragHandle: Equatable {
    case start
    case end
    case body
    case point(Int)
}

extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGSize) -> CGPoint {
        CGPoint(x: lhs.x + rhs.width, y: lhs.y + rhs.height)
    }
}

func distanceFromPoint(_ point: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
    guard points.count > 1 else { return .greatestFiniteMagnitude }
    var best = CGFloat.greatestFiniteMagnitude
    for i in 1..<points.count {
        best = min(best, distanceFromPoint(point, toSegmentStart: points[i - 1], end: points[i]))
    }
    return best
}

private func distanceFromPoint(_ point: CGPoint, toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let len2 = dx * dx + dy * dy
    guard len2 > 0.001 else {
        return hypot(point.x - start.x, point.y - start.y)
    }
    let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / len2))
    let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
    return hypot(point.x - projection.x, point.y - projection.y)
}
