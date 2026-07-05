import Cocoa
import SwiftUI
import CoreGraphics
import SparkleRecorderCore

@available(macOS 14.0, *)
private final class CaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@available(macOS 14.0, *)
private struct TextPickerView: View {
    let image: CGImage
    let screenFrame: CGRect
    let contentFrame: CGRect?
    
    struct MappedDetection: Identifiable {
        let id = UUID()
        let rect: CGRect
        let det: TextDetection
    }

    @State private var mappedDetections: [MappedDetection] = []
    @State private var isProcessing = true
    @State private var isArmed = false
    @State private var armSecondsRemaining = 3
    @State private var mouseLocation: CGPoint? = nil
    
    var onPicked: ((TextAnchor) -> Void)?
    
    private var targetFrame: CGRect {
        contentFrame ?? screenFrame
    }
    
    private var statusText: String {
        if isProcessing {
            return NSLocalizedString("Scanning for text...", comment: "")
        }
        if !isArmed {
            return String(format: NSLocalizedString("Ready in %ds. Move to the target text.", comment: ""), max(1, armSecondsRemaining))
        }
        if mappedDetections.isEmpty {
            return NSLocalizedString("No readable text found. Press ESC to cancel.", comment: "")
        }
        return NSLocalizedString("Point near the text to select. Click to confirm.", comment: "")
    }
    
    private func nearestDetectionIndex(to location: CGPoint?) -> Int? {
        guard let loc = location, isArmed, !mappedDetections.isEmpty else { return nil }
        var minDistanceSq: CGFloat = .infinity
        var nearestIndex: Int? = nil
        
        for (i, mapped) in mappedDetections.enumerated() {
            let center = CGPoint(x: mapped.rect.midX, y: mapped.rect.midY)
            let dx = center.x - loc.x
            let dy = center.y - loc.y
            let distSq = dx*dx + dy*dy
            if distSq < minDistanceSq {
                minDistanceSq = distSq
                nearestIndex = i
            }
        }
        return nearestIndex
    }
    
    var body: some View {
        ZStack {
            // Background screen dimming
            Color.black.opacity(0.5)
                .frame(width: screenFrame.width, height: screenFrame.height)
            
            // Draw the captured image
            if let frame = contentFrame {
                // Render the OCR source image at its real content-frame position.
                Image(decorative: image, scale: 1.0, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX - screenFrame.minX, y: frame.midY - screenFrame.minY)
                    .shadow(radius: 15)
            } else {
                // Full screen capture
                Image(decorative: image, scale: 1.0, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: screenFrame.width, height: screenFrame.height)
            }
            
            if isProcessing || !isArmed || mappedDetections.isEmpty {
                VStack(spacing: 16) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(1.2)
                            .progressViewStyle(CircularProgressViewStyle())
                    } else if !isArmed {
                        Text("\(max(1, armSecondsRemaining))")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Brand.sigAmber)
                    } else {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(statusText)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .padding(32)
                .background(.regularMaterial)
                .cornerRadius(12)
                .shadow(radius: 10)
                .transition(.opacity)
            } else if isArmed {
                let nearestIdx = nearestDetectionIndex(to: mouseLocation)
                // Draw interactive text rectangles
                GeometryReader { geo in
                    ForEach(0..<mappedDetections.count, id: \.self) { i in
                        let mapped = mappedDetections[i]
                        
                        DetectionBoxView(
                            rect: mapped.rect,
                            det: mapped.det,
                            screenFrame: screenFrame,
                            targetFrame: targetFrame,
                            isHovered: i == nearestIdx
                        )
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let loc):
                        mouseLocation = loc
                    case .ended:
                        mouseLocation = nil
                    }
                }
                .onTapGesture(coordinateSpace: .local) { loc in
                    if let idx = nearestDetectionIndex(to: loc) {
                        let mapped = mappedDetections[idx]
                        pick(det: mapped.det, rect: mapped.rect)
                    }
                }
                .onHover { hover in
                    if hover {
                        NSCursor.crosshair.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                .transition(.opacity)
            }
            
            // Instruction panel
            VStack {
                Spacer()
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(8)
                    .padding(.bottom, 40)
            }
        }
        .frame(width: screenFrame.width, height: screenFrame.height)
        .animation(.easeInOut, value: isProcessing)
        .animation(.easeInOut, value: isArmed)
        .onAppear {
            startArmingCountdown()
            Task {
                do {
                    let detector = VisionDetector()
                    let results = try await detector.detectText(in: image)
                    let filtered = results.filter { Self.isDisplayable($0, in: targetFrame) }
                    
                    let mapped = filtered.map { det -> MappedDetection in
                        let r = CGRect(
                            x: (targetFrame.minX - screenFrame.minX) + det.boundingBox.minX * targetFrame.width,
                            y: (targetFrame.minY - screenFrame.minY) + det.boundingBox.minY * targetFrame.height,
                            width: det.boundingBox.width * targetFrame.width,
                            height: det.boundingBox.height * targetFrame.height
                        )
                        return MappedDetection(rect: r, det: det)
                    }
                    
                    DispatchQueue.main.async {
                        self.mappedDetections = mapped
                        self.isProcessing = false
                    }
                } catch {
                    print("Failed to detect text: \(error)")
                    DispatchQueue.main.async {
                        self.isProcessing = false
                    }
                }
            }
        }
    }
    
    private func startArmingCountdown() {
        Task {
            await MainActor.run {
                armSecondsRemaining = 3
                isArmed = false
            }
            for second in stride(from: 3, through: 1, by: -1) {
                await MainActor.run {
                    armSecondsRemaining = second
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            await MainActor.run {
                armSecondsRemaining = 0
                isArmed = true
            }
        }
    }
    
    private static func isDisplayable(_ detection: TextDetection, in targetFrame: CGRect) -> Bool {
        let text = detection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        
        let width = detection.boundingBox.width * targetFrame.width
        let height = detection.boundingBox.height * targetFrame.height
        let area = width * height
        return width >= 10 && height >= 8 && area >= 240
    }
    
    private func pick(det: TextDetection, rect: CGRect) {
        let observedScreenRect = CGRect(
            x: screenFrame.minX + rect.minX,
            y: screenFrame.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )
        let searchScreenRect = defaultSearchRegion(for: observedScreenRect, in: targetFrame)
        let fallback = PointValue(
            x: screenFrame.minX + rect.midX,
            y: screenFrame.minY + rect.midY
        )
        let normalizedObserved = RectValue.normalized(rect: observedScreenRect, in: targetFrame)
        let normalizedSearch = RectValue.normalized(rect: searchScreenRect, in: targetFrame)
        let normalizedFallback = PointValue.normalized(point: CGPoint(x: fallback.x, y: fallback.y), in: targetFrame)
        
        let anchor = TextAnchor(
            text: det.text,
            matchMode: .contains,
            observedFrame: RectValue(rect: observedScreenRect),
            searchRegion: RectValue(rect: searchScreenRect),
            occurrenceHint: nil,
            coordinateFallback: fallback,
            observedContentNormalizedFrame: normalizedObserved,
            searchContentNormalizedRegion: normalizedSearch,
            coordinateFallbackContentNormalized: normalizedFallback
        )
        onPicked?(anchor)
    }
    
    private func defaultSearchRegion(for frame: CGRect, in bounds: CGRect) -> CGRect {
        frame
            .insetBy(dx: -max(120, frame.width), dy: -max(80, frame.height))
            .intersection(bounds)
    }
}

@available(macOS 14.0, *)
private struct DetectionBoxView: View {
    let rect: CGRect
    let det: TextDetection
    let screenFrame: CGRect
    let targetFrame: CGRect
    let isHovered: Bool
    
    private var observedScreenRect: CGRect {
        CGRect(
            x: screenFrame.minX + rect.minX,
            y: screenFrame.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )
    }
    
    private var searchScreenRect: CGRect {
        defaultSearchRegion(for: observedScreenRect, in: targetFrame)
    }
    
    private var searchLocalRect: CGRect {
        CGRect(
            x: searchScreenRect.minX - screenFrame.minX,
            y: searchScreenRect.minY - screenFrame.minY,
            width: searchScreenRect.width,
            height: searchScreenRect.height
        )
    }
    
    var body: some View {
        ZStack {
            if isHovered {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.orange.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.orange.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [7, 4]))
                    )
                    .frame(width: searchLocalRect.width, height: searchLocalRect.height)
                    .position(x: searchLocalRect.midX, y: searchLocalRect.midY)
                    .allowsHitTesting(false)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(det.text)
                        .font(.system(size: 12, weight: .semibold))
                    Text(String(format: NSLocalizedString("Text box %d×%d · search %d×%d", comment: ""), Int(rect.width), Int(rect.height), Int(searchLocalRect.width), Int(searchLocalRect.height)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.regularMaterial)
                .clipShape(.rect(cornerRadius: 7))
                .shadow(radius: 6)
                .position(x: rect.midX, y: max(24, rect.minY - 24))
                .allowsHitTesting(false)
            }
            
            RoundedRectangle(cornerRadius: 4)
                .fill((isHovered ? Brand.sigAmber : Color.green).opacity(isHovered ? 0.28 : 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isHovered ? Brand.sigAmber : Color.green, lineWidth: isHovered ? 3 : 2)
                )
                .frame(width: rect.width, height: rect.height)
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .position(x: rect.midX, y: rect.midY)
        }
        .frame(width: screenFrame.width, height: screenFrame.height, alignment: .topLeading)
        .zIndex(isHovered ? 1000 : 0)
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.7, blendDuration: 0), value: isHovered)
    }
    
    private func defaultSearchRegion(for frame: CGRect, in bounds: CGRect) -> CGRect {
        frame
            .insetBy(dx: -max(120, frame.width), dy: -max(80, frame.height))
            .intersection(bounds)
    }
}

@available(macOS 14.0, *)
@MainActor
public final class TextPickerOverlay {
    public static let shared = TextPickerOverlay()
    
    private var captureWindow: NSWindow?
    private var eventMonitor: Any?
    
    public var onPicked: ((TextAnchor) -> Void)?
    public var onCancelled: (() -> Void)?
    
    private static func topSpaceFrame(for screen: NSScreen) -> CGRect {
        guard let mainScreen = NSScreen.screens.first else { return screen.frame }
        let mainHeight = mainScreen.frame.height
        return CGRect(
            x: screen.frame.minX,
            y: mainHeight - (screen.frame.minY + screen.frame.height),
            width: screen.frame.width,
            height: screen.frame.height
        )
    }
    
    public func start(targetSurface: PlaybackSurface? = nil) {
        stop()
        
        Task { @MainActor in
            var capturedImage: CGImage? = nil
            var resolvedWindowFrame: CGRect? = nil
            var resolvedContentFrame: CGRect? = nil
            var targetScreen = NSScreen.main ?? NSScreen.screens.first
            
            if let surface = targetSurface, let bid = surface.bundleIdentifier {
                let tracker = WindowTracker()
                let frames = tracker.resolveCurrentFrames(for: ["target": surface])
                if let frame = frames["target"] {
                    let winFrame = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
                    resolvedWindowFrame = winFrame
                    
                    let pid = surface.bundleIdentifier.flatMap { bundleId in
                        NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId })?.processIdentifier
                    }
                    let content = CoordinateMapper.resolveContentFrame(for: pid, outerFrame: frame).frame
                    if content.width > 8, content.height > 8 {
                        resolvedContentFrame = content
                    }
                    
                    // Find screen containing window frame
                    if let mainScreen = NSScreen.screens.first {
                        let cocoaCenter = CGPoint(x: winFrame.midX, y: mainScreen.frame.height - winFrame.midY)
                        if let screen = NSScreen.screens.first(where: { NSMouseInRect(cocoaCenter, $0.frame, false) }) {
                            targetScreen = screen
                        }
                    }
                    
                    // Try to capture only the window
                    capturedImage = try? await ScreenCaptureService.shared.captureWindow(bundleIdentifier: bid, title: surface.windowTitle)
                    if let image = capturedImage,
                       let contentFrame = resolvedContentFrame,
                       let cropped = Self.crop(image: image, sourceFrame: winFrame, targetFrame: contentFrame) {
                        capturedImage = cropped
                    } else {
                        resolvedContentFrame = resolvedWindowFrame
                    }
                }
            }
            
            guard let target = targetScreen else { return }
            let displayID = (target.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
            
            let finalImage: CGImage
            if let img = capturedImage {
                finalImage = img
            } else {
                guard let img = try? await ScreenCaptureService.shared.captureDisplay(displayID: displayID) else {
                    self.onCancelled?()
                    return
                }
                finalImage = img
                resolvedContentFrame = nil // Fallback to full screen if window capture fails
            }
            
            self.showOverlay(image: finalImage, screen: target, contentFrame: resolvedContentFrame)
        }
    }
    
    private static func crop(image: CGImage, sourceFrame: CGRect, targetFrame: CGRect) -> CGImage? {
        let clipped = targetFrame.intersection(sourceFrame)
        guard !clipped.isNull, clipped.width > 1, clipped.height > 1 else { return nil }
        
        let nx = (clipped.minX - sourceFrame.minX) / max(1, sourceFrame.width)
        let ny = (clipped.minY - sourceFrame.minY) / max(1, sourceFrame.height)
        let nw = clipped.width / max(1, sourceFrame.width)
        let nh = clipped.height / max(1, sourceFrame.height)
        let pixelRect = CGRect(
            x: nx * CGFloat(image.width),
            y: ny * CGFloat(image.height),
            width: nw * CGFloat(image.width),
            height: nh * CGFloat(image.height)
        ).integral
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        return image.cropping(to: pixelRect.intersection(bounds))
    }
    
    private func showOverlay(image: CGImage, screen: NSScreen, contentFrame: CGRect?) {
        let screenFrame = TextPickerOverlay.topSpaceFrame(for: screen)
        
        let win = CaptureWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.acceptsMouseMovedEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        
        let view = TextPickerView(image: image, screenFrame: screenFrame, contentFrame: contentFrame) { [weak self] anchor in
            self?.stop()
            self?.onPicked?(anchor)
        }
        
        win.contentView = NSHostingView(rootView: view)
        self.captureWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Listen for ESC globally (local monitor) to cancel
        self.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.stop()
                self?.onCancelled?()
                return nil // consume event
            }
            return event
        }
    }
    
    public func stop() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        captureWindow?.orderOut(nil)
        captureWindow = nil
    }
}

private extension RectValue {
    init(rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
    
    static func normalized(rect: CGRect, in bounds: CGRect) -> RectValue {
        RectValue(
            x: bounds.width > 0 ? (rect.minX - bounds.minX) / bounds.width : 0,
            y: bounds.height > 0 ? (rect.minY - bounds.minY) / bounds.height : 0,
            width: bounds.width > 0 ? rect.width / bounds.width : 0,
            height: bounds.height > 0 ? rect.height / bounds.height : 0
        )
    }
}

private extension PointValue {
    static func normalized(point: CGPoint, in bounds: CGRect) -> PointValue {
        PointValue(
            x: bounds.width > 0 ? (point.x - bounds.minX) / bounds.width : 0,
            y: bounds.height > 0 ? (point.y - bounds.minY) / bounds.height : 0
        )
    }
}
