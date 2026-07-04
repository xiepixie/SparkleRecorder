import Cocoa
import SwiftUI
import Combine
import TinyRecorderCore
import UniformTypeIdentifiers

// MARK: - Window controller

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    init<V: View>(rootView: V) {
        let host = NSHostingController(rootView: rootView)
        let win = NSWindow(contentViewController: host)
        win.title = NSLocalizedString("Macro Editor", comment: "")
        win.setContentSize(NSSize(width: 1040, height: 720))
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        win.minSize = NSSize(width: 820, height: 580)
        win.isReleasedWhenClosed = false
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .visible
        win.isMovableByWindowBackground = false
        win.backgroundColor = .clear
        win.setFrameAutosaveName("TinyRecorder.MacroEditor")
        super.init(window: win)
        win.delegate = self
        if win.frameAutosaveName.isEmpty { win.center() }
    }
    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        CoordinatePreviewOverlay.shared.hide()
    }
}

struct CoordinateResolutionContext {
    let dx: CGFloat
    let dy: CGFloat
    
    func resolve(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + dx, y: point.y + dy)
    }
}

// MARK: - Row model

struct ActionRow: Identifiable {
    var id: UUID { group.id }
    let group: ActionGroup
}

struct DragEditSession {
    let groupID: UUID
    let eventIndices: [Int]
    let snapshot: [RecordedEvent]
}

// MARK: - Editor view

struct EditorView: View {
    let controller: MenuBarController
    @EnvironmentObject var recorder: Recorder
    @EnvironmentObject var library: MacroLibrary
    @EnvironmentObject var state: AppState
    @Environment(\.undoManager) private var undoManager

    @State private var selection: Set<UUID> = []
    @State private var hideMouseMoves = false
    @State private var showAllPaths = false
    @State private var stretchFactor: Double = 1.0
    @State private var shiftMs: Double = 100

    @State private var inspTime: String = ""
    @State private var inspX: String = ""
    @State private var inspY: String = ""
    @State private var inspEndX: String = ""
    @State private var inspEndY: String = ""
    @State private var inspKey: String = ""
    @State private var inspFlags: UInt64 = 0
    @State private var activeDragSession: DragEditSession? = nil
    @State private var hoveredRow: UUID? = nil
    @State private var smartMergeGestures = true
    @AppStorage("showOverlayPreview") var showOverlayPreview = true

    @State private var cachedRows: [ActionRow] = []

    var rows: [ActionRow] { cachedRows }

    private func updateCachedRows() {
        var options = EventGroupingOptions()
        options.disableGrouping = !smartMergeGestures
        let list = EventGrouper(options: options).group(recorder.events, liveDuration: recorder.liveDuration)
        cachedRows = list.enumerated().compactMap { idx, grp in
            if hideMouseMoves && grp.kind == .mouseMove {
                return nil
            }
            return ActionRow(group: grp)
        }
        updatePreview()
    }

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .windowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            PlayerStateListener()

            VStack(spacing: 0) {
                EditorToolbar(
                    macro: library.currentMacro,
                    rowCount: recorder.events.count,
                    duration: recorder.events.last?.time ?? 0,
                    hideMouseMoves: $hideMouseMoves,
                    showAllPaths: $showAllPaths,
                    showOverlayPreview: $showOverlayPreview,
                    smartMergeGestures: $smartMergeGestures,
                    onExport:  { controller.exportAsScript() }
                )

                HSplitView {
                    EditorSidebar(
                        selection: $selection,
                        rows: rows,
                        stretchFactor: $stretchFactor,
                        shiftMs: $shiftMs,
                        inspTime: $inspTime,
                        inspX: $inspX,
                        inspY: $inspY,
                        inspEndX: $inspEndX,
                        inspEndY: $inspEndY,
                        inspKey: $inspKey,
                        inspFlags: $inspFlags,
                        recorder: recorder,
                        onLoadInspector: loadInspector,
                        onUpdatePreview: updatePreview,
                        onPickCoordinate: { isEndPoint in
                            self.startPickingCoordinate(isEndPoint: isEndPoint)
                        }
                    )
                    .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)

                    VStack(spacing: 0) {
                        EditorTimeline(
                            events: recorder.events,
                            groups: rows.map(\.group),
                            selection: $selection
                        )
                        .padding(14)

                        ActionListView(rows: rows, selection: $selection)
                    }
                    .frame(minWidth: 420)
                }

                EditorFooter(eventCount: recorder.events.count,
                             selectedCount: selection.count,
                             duration: recorder.events.last?.time ?? 0)
            }
        }
        .frame(minWidth: 820, minHeight: 580)
        .onAppear {
            updateCachedRows()
        }
        .onChange(of: selection) {
            loadInspector()
            updatePreview()
        }
        .onChange(of: recorder.events) {
            updateCachedRows()
            updatePreview()
            controller.persistEdits()
        }
        .onChange(of: hideMouseMoves) {
            updateCachedRows()
        }
        .onChange(of: showAllPaths) {
            updatePreview()
        }
        .onChange(of: smartMergeGestures) {
            updateCachedRows()
        }
        .onChange(of: showOverlayPreview) {
            updatePreview()
        }
        // The active macro changed under us (new recording saved, card clicked,
        // macro deleted) — stale indices would corrupt the new buffer.
        .onChange(of: library.currentMacroID) {
            selection.removeAll()
            CoordinatePreviewOverlay.shared.hide()
            updateCachedRows()
        }
        .onDisappear {
            controller.persistEdits()
            CoordinatePreviewOverlay.shared.hide()
        }
    }

    private func loadInspector() {
        if selection.count == 1, let groupID = selection.first,
           let row = rows.first(where: { $0.id == groupID }) {
            let grp = row.group
            if grp.kind == .wait {
                inspTime = String(format: "%.4f", grp.duration)
            } else {
                inspTime = String(format: "%.4f", grp.startTime)
            }
            if let sp = grp.startPoint {
                inspX = String(format: "%.0f", sp.x)
                inspY = String(format: "%.0f", sp.y)
            } else {
                inspX = ""; inspY = ""
            }
            if let ep = grp.endPoint {
                inspEndX = String(format: "%.0f", ep.x)
                inspEndY = String(format: "%.0f", ep.y)
            } else {
                inspEndX = ""; inspEndY = ""
            }
            if let kc = grp.keyCode {
                inspKey = String(kc)
            } else {
                inspKey = ""
            }
            inspFlags = grp.keyFlags ?? 0
        } else {
            inspTime = ""; inspX = ""; inspY = ""; inspEndX = ""; inspEndY = ""; inspKey = ""; inspFlags = 0
        }
    }

    private func updatePreview() {
        var actionsToPreview: [PreviewAction] = []
        
        let groupsToScan: [(id: UUID, grp: ActionGroup)]
        if showAllPaths {
            groupsToScan = rows.map { ($0.id, $0.group) }
        } else {
            groupsToScan = rows.compactMap { row in
                guard selection.contains(row.id) else { return nil }
                return (row.id, row.group)
            }
        }
        
        let resolutionContext = makeResolutionContext(for: library.currentMacro)
        
        for (orderIdx, item) in groupsToScan.enumerated() {
            let grp = item.grp
            let startPt = grp.startPoint.map(resolutionContext.resolve)
            let resolvedPath = grp.path.map(resolutionContext.resolve)
            
            let color: Color
            switch grp.kind {
            case .click, .doubleClick: color = Brand.sigGreen
            case .longPress: color = Brand.sigGreen
            case .drag: color = Brand.sigViolet
            case .scroll: color = Brand.sigTeal
            case .keyPress: color = Brand.sigBlue
            case .keyHold: color = Brand.sigBlue
            case .wait: color = .gray
            case .mouseMove: color = .secondary
            }
            
            if grp.kind == .wait || (grp.kind == .mouseMove && hideMouseMoves) {
                continue
            }
            
            actionsToPreview.append(PreviewAction(
                id: item.id,
                kind: grp.kind,
                selectedPoint: startPt,
                dragPath: resolvedPath,
                themeColor: color,
                order: orderIdx + 1
            ))
        }
        
        if !actionsToPreview.isEmpty && showOverlayPreview {
            CoordinatePreviewOverlay.shared.onDragStarted = { [weak recorder] groupID in
                guard let rec = recorder else { return }
                if let grp = self.rows.first(where: { $0.id == groupID })?.group {
                    self.activeDragSession = DragEditSession(
                        groupID: groupID,
                        eventIndices: grp.eventIndices,
                        snapshot: rec.events
                    )
                }
            }
            // No onChanged callbacks — visual feedback is handled by
            // @State in TargetCrosshairView. Events are only modified on release.
            CoordinatePreviewOverlay.shared.onDragStartPointEnded = { [weak recorder] groupID, dx, dy in
                guard let session = self.activeDragSession, let rec = recorder else { return }
                rec.loadEvents(session.snapshot)
                self.activeDragSession = nil
                self.withUndo(NSLocalizedString("Move Start Point", comment: "")) {
                    rec.translateEvents(at: session.eventIndices, dx: dx, dy: dy)
                }
                self.loadInspector()
            }
            CoordinatePreviewOverlay.shared.onDragEndPointEnded = { [weak recorder] groupID, dx, dy in
                guard let session = self.activeDragSession, let rec = recorder else { return }
                rec.loadEvents(session.snapshot)
                self.activeDragSession = nil
                self.withUndo(NSLocalizedString("Adjust Swipe Destination", comment: "")) {
                    if let grp = self.rows.first(where: { $0.id == session.groupID })?.group {
                        if let start = grp.startPoint, let end = grp.endPoint {
                            let newEnd = CGPoint(x: end.x + dx, y: end.y + dy)
                            rec.conformPath(at: session.eventIndices, startPoint: start, oldEndPoint: end, newEndPoint: newEnd)
                        }
                    }
                }
                self.loadInspector()
            }
            CoordinatePreviewOverlay.shared.show(actions: actionsToPreview, selectedActionID: selection.count == 1 ? selection.first : nil)
        } else {
            CoordinatePreviewOverlay.shared.hide()
        }
    }

    private func withUndo(_ name: String, _ mutate: () -> Void) {
        let snapshot = recorder.events
        undoManager?.registerUndo(withTarget: recorder) { [weak undoManager] rec in
            let redoSnapshot = rec.events
            rec.loadEvents(snapshot)
            undoManager?.registerUndo(withTarget: rec) { rec2 in
                rec2.loadEvents(redoSnapshot)
            }
        }
        undoManager?.setActionName(name)
        mutate()
    }

    private func startPickingCoordinate(isEndPoint: Bool) {
        // Hide the preview overlay during coordinate picking so it doesn't intercept mouse events
        CoordinatePreviewOverlay.shared.hide()
        
        let editorWin = NSApp.windows.first(where: { $0.title == NSLocalizedString("Macro Editor", comment: "") })
        editorWin?.orderOut(nil)
        
        CoordinatePickerOverlay.shared.onPicked = { [weak recorder] pt in
            editorWin?.makeKeyAndOrderFront(nil)
            
            guard selection.count == 1, let selectId = selection.first,
                  let row = rows.first(where: { $0.id == selectId }) else { return }
            
            let grp = row.group
            let currentMacro = library.currentMacro
            
            DispatchQueue.global(qos: .userInitiated).async { [weak recorder] in
                var finalPt = pt
                if let macro = currentMacro, macro.followWindowOffset, let surface = macro.surface {
                    var delta = CGPoint.zero
                    if let bid = surface.bundleIdentifier {
                        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
                        if let app = apps.first {
                            let pid = app.processIdentifier
                            let axApp = AXUIElementCreateApplication(pid)
                            var focusedWindowRef: CFTypeRef?
                            let res = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
                            if res == .success, let focusedWindow = focusedWindowRef {
                                var posRef: CFTypeRef?
                                let posRes = AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXPositionAttribute as CFString, &posRef)
                                if posRes == .success, let posVal = posRef {
                                    var pos = CGPoint.zero
                                    AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
                                    delta = CGPoint(x: pos.x - surface.recordedFrame.x, y: pos.y - surface.recordedFrame.y)
                                }
                            }
                        }
                    }
                    finalPt = CGPoint(x: pt.x - delta.x, y: pt.y - delta.y)
                }
                
                DispatchQueue.main.async { [weak recorder] in
                    guard let rec = recorder else { return }
                    
                    if isEndPoint {
                        self.withUndo(NSLocalizedString("Pick End Coordinate", comment: "")) {
                            if let start = grp.startPoint, let end = grp.endPoint {
                                rec.conformPath(at: grp.eventIndices, startPoint: start, oldEndPoint: end, newEndPoint: finalPt)
                            }
                        }
                    } else {
                        self.withUndo(NSLocalizedString("Pick Coordinate", comment: "")) {
                            let oldStart = grp.startPoint ?? CGPoint.zero
                            let dx = finalPt.x - oldStart.x
                            let dy = finalPt.y - oldStart.y
                            rec.translateEvents(at: grp.eventIndices, dx: dx, dy: dy)
                        }
                    }
                    
                    self.loadInspector()
                    self.updatePreview() // This restores the preview overlay
                }
            }
        }
        
        CoordinatePickerOverlay.shared.onCancelled = {
            editorWin?.makeKeyAndOrderFront(nil)
            self.updatePreview() // Restore the preview overlay
        }
        
        CoordinatePickerOverlay.shared.start()
    }

    private func makeResolutionContext(for macro: SavedMacro?) -> CoordinateResolutionContext {
        guard let macro = macro, macro.followWindowOffset, let surface = macro.surface else {
            return CoordinateResolutionContext(dx: 0, dy: 0)
        }
        if let bid = surface.bundleIdentifier {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            if let app = apps.first {
                let pid = app.processIdentifier
                let axApp = AXUIElementCreateApplication(pid)
                var focusedWindowRef: CFTypeRef?
                let res = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
                if res == .success, let focusedWindow = focusedWindowRef {
                    var posRef: CFTypeRef?
                    let posRes = AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXPositionAttribute as CFString, &posRef)
                    if posRes == .success, let posVal = posRef {
                        var pos = CGPoint.zero
                        AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
                        let dx = pos.x - surface.recordedFrame.x
                        let dy = pos.y - surface.recordedFrame.y
                        return CoordinateResolutionContext(dx: dx, dy: dy)
                    }
                }
            }
        }
        return CoordinateResolutionContext(dx: 0, dy: 0)
    }}

// MARK: - Header

private struct EditorToolbar: View {
    let macro: SavedMacro?
    let rowCount: Int
    let duration: TimeInterval
    @Binding var hideMouseMoves: Bool
    @Binding var showAllPaths: Bool
    @Binding var showOverlayPreview: Bool
    @Binding var smartMergeGestures: Bool
    let onExport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                BrandMark(size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(macro?.name ?? NSLocalizedString("Untitled macro", comment: ""))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Label(String(format: NSLocalizedString("%d events", comment: ""), rowCount), systemImage: "wave.3.right")
                        Text("·").foregroundStyle(.tertiary)
                        Label(formatDuration(duration), systemImage: "clock")
                        if let m = macro {
                            Text("·").foregroundStyle(.tertiary)
                            Text(String(format: NSLocalizedString("edited %@", comment: ""), RelativeTime.string(from: m.modifiedAt)))
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                }

                Spacer()

                // Show Preview Overlay switch
                Toggle(isOn: $showOverlayPreview) {
                    Label(NSLocalizedString("Show Preview Overlay", comment: ""), systemImage: "eye")
                        .font(.system(size: 11, weight: .medium))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(.blue)
                
                // Show all paths switch
                Toggle(isOn: $showAllPaths) {
                    Label(NSLocalizedString("Show All Paths", comment: ""), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 11, weight: .medium))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(.purple)

                // Hide mouse moves switch
                Toggle(isOn: $hideMouseMoves) {
                    Label(NSLocalizedString("Hide mouse moves", comment: ""), systemImage: "eye.slash.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(.green)

                // Smart Merge Gestures switch
                Toggle(isOn: $smartMergeGestures) {
                    Label(NSLocalizedString("Merge Gestures", comment: ""), systemImage: "squareshape.squareshape")
                        .font(.system(size: 11, weight: .medium))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(.orange)

                // Export
                Button(action: onExport) {
                    Label(NSLocalizedString("Export as Command…", comment: ""), systemImage: "square.and.arrow.up")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .controlSize(.regular)
                .buttonStyle(.bordered)
                .help(NSLocalizedString("Exports a double-clickable .command script", comment: ""))

            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Divider()
        }
        .background(VisualEffectBackground(material: .titlebar, blendingMode: .withinWindow))
    }
}

private struct PlayerStateListener: View {
    @EnvironmentObject var player: Player

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: player.isPlaying) { oldPlaying, playing in
                CoordinatePreviewOverlay.shared.setIgnoresMouseEvents(playing)
            }
    }
}

// MARK: - Timeline

private struct TimelinePlayheadView: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var library: MacroLibrary
    let totalDuration: TimeInterval
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        if player.isPlaying && totalDuration > 0 {
            Rectangle()
                .fill(Brand.accent(library.currentMacro?.accent))
                .frame(width: 2, height: height)
                .position(x: CGFloat(player.progress) * width, y: height / 2)
        }
    }
}

private struct EditorTimeline: View {
    @EnvironmentObject var library: MacroLibrary
    let events: [RecordedEvent]
    let groups: [ActionGroup]
    @Binding var selection: Set<UUID>

    @State private var hoverFraction: Double?
    @State private var dragRange: (start: Double, end: Double)?
    @GestureState private var isDragging = false

    private var totalDuration: TimeInterval { events.last?.time ?? 0 }

    private struct SampledEvent: Identifiable {
        let id: Int
        let event: RecordedEvent
    }

    private var sampledEvents: [SampledEvent] {
        guard !events.isEmpty else { return [] }
        let maxBars = 800
        let n = min(events.count, maxBars)
        let stride = max(1, events.count / n)
        var result: [SampledEvent] = []
        var i = 0
        while i < events.count {
            result.append(SampledEvent(id: i, event: events[i]))
            i += stride
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NSLocalizedString("TIMELINE", comment: ""))
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Spacer()
                LegendChip(label: NSLocalizedString("Keys", comment: ""),    tint: Brand.sigBlue)
                LegendChip(label: NSLocalizedString("Clicks", comment: ""),  tint: Brand.sigGreen)
                LegendChip(label: NSLocalizedString("Scrolls", comment: ""), tint: Brand.sigTeal)
                LegendChip(label: NSLocalizedString("Drags", comment: ""),   tint: Brand.sigViolet)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                        )

                    // Event bars
                    Canvas { context, size in
                        guard totalDuration > 0 else { return }
                        let h = size.height
                        let w = size.width
                        for sampled in sampledEvents {
                            let ev = sampled.event
                            let x = CGFloat(ev.time / totalDuration) * w
                            let isImpact = Brand.isImpact(ev.kind)
                            let rectHeight = isImpact ? h * 0.75 : h * 0.45
                            let rect = CGRect(x: x - 1, y: (h - rectHeight) / 2, width: 2, height: rectHeight)
                            let color = Brand.eventColor(ev.kind).opacity(isImpact ? 1.0 : 0.7)
                            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
                        }
                    }

                    // Selection range
                    if let r = selectionRange(in: w) {
                        let barHalfWidth: CGFloat = 1.0
                        let startX = r.start - barHalfWidth
                        let boxWidth = (r.end - r.start) + (barHalfWidth * 2)
                        
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.accentColor.opacity(0.18))
                            .overlay(
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: 1.5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            )
                            .frame(width: max(2, boxWidth), height: h)
                            .offset(x: startX)
                    }

                    // Drag preview
                    if let dr = dragRange {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: max(2, CGFloat(abs(dr.end - dr.start)) * w), height: h)
                            .offset(x: CGFloat(min(dr.start, dr.end)) * w)
                    }

                    // Playhead
                    TimelinePlayheadView(totalDuration: totalDuration, width: w, height: h)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isDragging) { _, s, _ in s = true }
                        .onChanged { val in
                            let s = Double(max(0, min(1, val.startLocation.x / w)))
                            let e = Double(max(0, min(1, val.location.x / w)))
                            dragRange = (s, e)
                        }
                        .onEnded { _ in
                            if let dr = dragRange {
                                let lo = min(dr.start, dr.end) * totalDuration
                                let hi = max(dr.start, dr.end) * totalDuration
                                var newSel: Set<UUID> = []
                                for grp in groups {
                                    if grp.startTime >= lo && grp.endTime <= hi {
                                        newSel.insert(grp.id)
                                    }
                                }
                                if newSel.isEmpty {
                                    // Select nearest group
                                    let target = (dr.start + dr.end) / 2 * totalDuration
                                    if let grp = nearestGroup(to: target) {
                                        selection = [grp.id]
                                    }
                                } else {
                                    selection = newSel
                                }
                            }
                            dragRange = nil
                        }
                )
            }
            .frame(height: 50)

            HStack {
                Text(formatTime(0))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(totalDuration / 2))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(totalDuration))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if let id = selection.first, selection.count == 1,
                   let grp = groups.first(where: { $0.id == id }) {
                    let themeColor = actionKindColor(grp.kind)
                    HStack(spacing: 4) {
                        Circle().fill(themeColor).frame(width: 6, height: 6)
                        Text(formatTime(grp.startTime))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(themeColor.opacity(0.12)))
                }
                Text(NSLocalizedString("Drag on timeline to select a range · ⌥-drag to extend", comment: ""))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func selectionRange(in width: CGFloat) -> (start: CGFloat, end: CGFloat)? {
        guard !selection.isEmpty, totalDuration > 0 else { return nil }
        var times: [TimeInterval] = []
        for grp in groups {
            if selection.contains(grp.id) {
                times.append(grp.startTime)
                times.append(grp.endTime)
            }
        }
        guard let lo = times.min(), let hi = times.max() else { return nil }
        let s = CGFloat(lo / totalDuration) * width
        let e = CGFloat(hi / totalDuration) * width
        return (s, e)
    }

    private func nearestGroup(to t: TimeInterval) -> ActionGroup? {
        guard !groups.isEmpty else { return nil }
        var bestGrp = groups[0]
        var bestDelta = TimeInterval.greatestFiniteMagnitude
        for grp in groups {
            let d = min(abs(grp.startTime - t), abs(grp.endTime - t))
            if d < bestDelta {
                bestDelta = d
                bestGrp = grp
            }
        }
        return bestGrp
    }

    private func formatTime(_ d: TimeInterval) -> String {
        let m = Int(d) / 60
        let s = Int(d) % 60
        let cs = Int((d - floor(d)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }

    private func eventColor(for kind: RecordedEvent.Kind) -> Color {
        Brand.eventColor(kind)
    }
}

private struct LegendChip: View {
    let label: String
    let tint: Color
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sidebar (tools + inspector)

private struct EditorSidebar: View {
    @Binding var selection: Set<UUID>
    let rows: [ActionRow]
    @Binding var stretchFactor: Double
    @Binding var shiftMs: Double
    @Binding var inspTime: String
    @Binding var inspX: String
    @Binding var inspY: String
    @Binding var inspEndX: String
    @Binding var inspEndY: String
    @Binding var inspKey: String
    @Binding var inspFlags: UInt64
    let recorder: Recorder
    let onLoadInspector: () -> Void
    let onUpdatePreview: () -> Void
    let onPickCoordinate: (Bool) -> Void

    @State private var insertWaitMs: Double = 1000
    @State private var confirmClearAll = false
    @State private var isRecordingKey = false
    @State private var recordedFlags: UInt64 = 0
    @State private var keyMonitor: Any? = nil
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Section 1: Inspector (Top Priority)
                section(NSLocalizedString("Inspector", comment: ""), icon: "info.circle") {
                    if selection.count == 1, let id = selection.first,
                       let row = rows.first(where: { $0.id == id }) {
                        let grp = row.group
                        HStack {
                            Image(systemName: actionKindIcon(grp.kind))
                                .foregroundStyle(actionKindColor(grp.kind))
                                .font(.system(size: 12))
                            VStack(alignment: .leading, spacing: 0) {
                                let actionNumber = (rows.firstIndex(where: { $0.id == id }) ?? 0) + 1
                                Text(String(format: NSLocalizedString("Action #%d", comment: ""), actionNumber))
                                    .font(.system(size: 11, weight: .semibold))
                                Text(humanActionKindName(grp.kind))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
 
                        labeledField(grp.kind == .wait ? NSLocalizedString("Duration (s)", comment: "") : NSLocalizedString("Time (s)", comment: ""), text: $inspTime)
                        
                        if grp.kind == .click || grp.kind == .doubleClick || grp.kind == .scroll || grp.kind == .longPress {
                            HStack(alignment: .bottom, spacing: 6) {
                                labeledField("X", text: $inspX)
                                labeledField("Y", text: $inspY)
                                Button {
                                    onPickCoordinate(false)
                                } label: {
                                    Image(systemName: "scope")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                                .help(NSLocalizedString("Pick coordinate from screen", comment: ""))
                            }
                        } else if grp.kind == .drag {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(NSLocalizedString("Start Position", comment: ""))
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                HStack(alignment: .bottom, spacing: 6) {
                                    labeledField("X", text: $inspX)
                                    labeledField("Y", text: $inspY)
                                    Button {
                                        onPickCoordinate(false)
                                    } label: {
                                        Image(systemName: "scope")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.regular)
                                    .help(NSLocalizedString("Pick coordinate from screen", comment: ""))
                                }
                                Text(NSLocalizedString("End Position", comment: ""))
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                HStack(alignment: .bottom, spacing: 6) {
                                    labeledField("X", text: $inspEndX)
                                    labeledField("Y", text: $inspEndY)
                                    Button {
                                        onPickCoordinate(true)
                                    } label: {
                                        Image(systemName: "scope")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.regular)
                                    .help(NSLocalizedString("Pick coordinate from screen", comment: ""))
                                }
                            }
                        }
                        
                        if grp.kind == .keyPress {
                            HStack {
                                Text(NSLocalizedString("Key code", comment: ""))
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if isRecordingKey {
                                    Button(action: stopRecordingKey) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "record.circle.fill")
                                                .foregroundColor(.red)
                                            let mods = modifierString(flags: recordedFlags)
                                            Text(mods.isEmpty ? NSLocalizedString("Press any key…", comment: "") : "\(mods) " + NSLocalizedString("Press any key…", comment: ""))
                                                .foregroundColor(.white)
                                        }
                                        .font(.system(size: 11, weight: .bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.8)))
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Button(action: startRecordingKey) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "keyboard")
                                            let currentCode = UInt16(inspKey) ?? grp.keyCode ?? 0
                                            Text(shortcutName(keyCode: currentCode, flags: inspFlags))
                                        }
                                        .font(.system(size: 11, weight: .semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            if !isRecordingKey {
                                labeledField(NSLocalizedString("Raw Code", comment: ""), text: $inspKey)
                            }
                        }
                    } else if selection.count > 1 {
                        emptyInspector(
                             icon: "square.stack",
                             title: String(format: NSLocalizedString("%d actions selected", comment: ""), selection.count),
                             subtitle: NSLocalizedString("Select one action to edit fields", comment: "")
                        )
                    } else {
                        emptyInspector(
                            icon: "hand.tap",
                            title: NSLocalizedString("No selection", comment: ""),
                            subtitle: NSLocalizedString("Click a row to inspect or edit", comment: "")
                        )
                    }
                }

                // Section 2: Selection / Edit Actions
                section(NSLocalizedString("Selection", comment: ""), icon: "checklist") {
                    Button(action: deleteSelected) {
                        Label(NSLocalizedString("Delete selected", comment: ""), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(selection.isEmpty)
                    .keyboardShortcut(.delete, modifiers: [])

                    Button(action: duplicateSelected) {
                        Label(NSLocalizedString("Duplicate selected", comment: ""), systemImage: "plus.square.on.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(selection.isEmpty)
                    .keyboardShortcut("d", modifiers: .command)

                    HStack(spacing: 6) {
                        Button(action: trimBefore) {
                            Label(NSLocalizedString("Trim before", comment: ""), systemImage: "arrow.left.to.line")
                        }
                        .frame(maxWidth: .infinity)
                        .help(NSLocalizedString("Delete every event before the selected one", comment: ""))

                        Button(action: trimAfter) {
                            Label(NSLocalizedString("Trim after", comment: ""), systemImage: "arrow.right.to.line")
                        }
                        .frame(maxWidth: .infinity)
                        .help(NSLocalizedString("Delete every event after the selected one", comment: ""))
                    }
                    .controlSize(.small)
                    .disabled(selection.count != 1)

                    Button(role: .destructive) {
                        confirmClearAll = true
                    } label: {
                        Label(NSLocalizedString("Clear all", comment: ""), systemImage: "trash.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(rows.isEmpty)
                    .confirmationDialog(
                        NSLocalizedString("Remove all events from this macro?", comment: ""),
                        isPresented: $confirmClearAll,
                        titleVisibility: .visible
                    ) {
                        Button(NSLocalizedString("Clear All Events", comment: ""), role: .destructive) { clearAll() }
                        Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
                    } message: {
                        Text(NSLocalizedString("You can undo this with ⌘Z while the editor is open.", comment: ""))
                    }
                }

                // Section 3: Insert Action
                section(NSLocalizedString("Insert action", comment: ""), icon: "plus.square") {
                    HStack(spacing: 6) {
                        Stepper(value: $insertWaitMs, in: 50...60000, step: 100) {
                            Text("\(Int(insertWaitMs)) ms")
                                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                        }
                        .controlSize(.small)
                    }
                    HStack(spacing: 6) {
                        Button(action: { insertAction(.wait) }) {
                            Label(NSLocalizedString("Wait", comment: ""), systemImage: "hourglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        
                        Button(action: { insertAction(.click) }) {
                            Label(NSLocalizedString("Click", comment: ""), systemImage: "hand.point.up.left")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    HStack(spacing: 6) {
                        Button(action: { insertAction(.drag) }) {
                            Label(NSLocalizedString("Drag", comment: ""), systemImage: "hand.draw")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button(action: { insertAction(.keyPress) }) {
                            Label(NSLocalizedString("Key", comment: ""), systemImage: "keyboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // Section 4: Time Adjustments (Merged Shift & Stretch)
                section(NSLocalizedString("Time Adjustments", comment: ""), icon: "timer") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("Shift Selected", comment: ""))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        HStack {
                            Stepper(value: $shiftMs, in: 10...5000, step: 50) {
                                Text("\(Int(shiftMs)) ms")
                                    .font(.system(size: 10, design: .monospaced).weight(.semibold))
                            }
                            .controlSize(.small)
                            Spacer()
                            Button(action: { shiftSelection(by: -shiftMs / 1000.0) }) {
                                Image(systemName: "gobackward")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(selection.isEmpty)
                            
                            Button(action: { shiftSelection(by: shiftMs / 1000.0) }) {
                                Image(systemName: "goforward")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(selection.isEmpty)
                        }
                    }
                    
                    Divider().padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(NSLocalizedString("Time Stretch", comment: ""))
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.2f×", stretchFactor))
                                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                        }
                        Slider(value: $stretchFactor, in: 0.25...4.0, step: 0.05)
                            .controlSize(.small)
                        HStack {
                            Button(NSLocalizedString("Reset", comment: "")) { stretchFactor = 1.0 }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                            Spacer()
                            Button(NSLocalizedString("Apply", comment: "")) { applyStretch() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(rows.isEmpty || abs(stretchFactor - 1.0) < 0.001)
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow))
        .onDisappear {
            stopRecordingKey()
        }
        .onChange(of: selection) {
            stopRecordingKey()
        }
    }

    private func startRecordingKey() {
        if keyMonitor != nil {
            stopRecordingKey()
            return
        }
        isRecordingKey = true
        recordedFlags = 0
        
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                DispatchQueue.main.async {
                    self.recordedFlags = UInt64(flags.rawValue)
                }
                return nil
            } else if event.type == .keyDown {
                let code = event.keyCode
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                DispatchQueue.main.async {
                    self.inspKey = "\(code)"
                    self.inspFlags = UInt64(flags.rawValue)
                    self.applyInspector()
                    self.stopRecordingKey()
                }
                return nil
            }
            return event
        }
    }
    
    private func stopRecordingKey() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        isRecordingKey = false
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.6)
            }
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(10)
                .cardSurface(cornerRadius: 10)
        }
    }

    @ViewBuilder
    private func emptyInspector(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.4)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.callout, design: .monospaced))
                .controlSize(.small)
                .onSubmit { applyInspector() }
        }
    }

    // MARK: - Actions

    private func withUndo(_ name: String, _ mutate: () -> Void) {
        let snapshot = recorder.events
        undoManager?.registerUndo(withTarget: recorder) { [weak undoManager] rec in
            let redoSnapshot = rec.events
            rec.loadEvents(snapshot)
            undoManager?.registerUndo(withTarget: rec) { rec2 in
                rec2.loadEvents(redoSnapshot)
            }
        }
        undoManager?.setActionName(name)
        mutate()
    }

    private func duplicateSelected() {
        let selectedGroups = selection.compactMap { groupID -> ActionGroup? in
            rows.first(where: { $0.id == groupID })?.group
        }
        var allIndices: [Int] = []
        for grp in selectedGroups {
            allIndices.append(contentsOf: grp.eventIndices)
        }
        guard !allIndices.isEmpty else { return }
        
        let sorted = allIndices.sorted()
        let count = sorted.count
        let afterIdx = (sorted.last! + 1)
        let copiesRange = afterIdx ..< (afterIdx + count)
        
        withUndo(NSLocalizedString("Duplicate Action", comment: "")) {
            recorder.duplicateEvents(at: allIndices)
        }
        
        DispatchQueue.main.async {
            let newRows = self.rows.filter { row in
                guard let firstIdx = row.group.eventIndices.first else { return false }
                return copiesRange.contains(firstIdx)
            }
            if !newRows.isEmpty {
                self.selection = Set(newRows.map(\.id))
            }
        }
    }

    private func deleteSelected() {
        let selectedGroups = selection.compactMap { groupID -> ActionGroup? in
            rows.first(where: { $0.id == groupID })?.group
        }
        var allIndices: [Int] = []
        var totalWaitDelta: TimeInterval = 0
        var trailingWaitDelta: TimeInterval = 0
        var waitCutoffTime: TimeInterval = .greatestFiniteMagnitude
        
        for grp in selectedGroups {
            if grp.kind == .wait {
                let waitDuration = grp.endTime - grp.startTime
                if waitDuration > 0 {
                    // Check if this is a trailing wait (no events after it)
                    let hasEventsAfter = recorder.events.contains(where: { $0.time >= grp.endTime })
                    if hasEventsAfter {
                        totalWaitDelta += waitDuration
                        if grp.endTime < waitCutoffTime {
                            waitCutoffTime = grp.endTime
                        }
                    } else {
                        trailingWaitDelta += waitDuration
                    }
                }
            } else {
                allIndices.append(contentsOf: grp.eventIndices)
            }
        }
        
        guard !allIndices.isEmpty || totalWaitDelta > 0 || trailingWaitDelta > 0 else { return }
        
        selection.removeAll()
        withUndo(NSLocalizedString("Delete Actions", comment: "")) {
            if !allIndices.isEmpty {
                recorder.deleteEvents(at: IndexSet(allIndices))
            }
            if totalWaitDelta > 0 {
                var subsequentIndices = IndexSet()
                for (idx, ev) in recorder.events.enumerated() {
                    if ev.time >= waitCutoffTime {
                        subsequentIndices.insert(idx)
                    }
                }
                if !subsequentIndices.isEmpty {
                    recorder.shiftTime(of: subsequentIndices, by: -totalWaitDelta)
                }
            }
            if trailingWaitDelta > 0 {
                recorder.setLiveDuration(recorder.liveDuration - trailingWaitDelta)
            }
        }
    }

    private func trimBefore() {
        guard selection.count == 1, let id = selection.first,
              let row = rows.first(where: { $0.id == id }) else { return }
        let grp = row.group
        guard let firstEventIdx = grp.eventIndices.first else { return }
        withUndo("Trim Before") {
            recorder.trimBefore(index: firstEventIdx)
        }
        selection = []
    }

    private func trimAfter() {
        guard selection.count == 1, let id = selection.first,
              let row = rows.first(where: { $0.id == id }) else { return }
        let grp = row.group
        guard let lastEventIdx = grp.eventIndices.last else { return }
        withUndo("Trim After") {
            recorder.trimAfter(index: lastEventIdx)
        }
        selection = []
    }

    private func clearAll() {
        selection.removeAll()
        withUndo("Clear All Events") {
            recorder.clearAll()
        }
    }

    private func insertAction(_ kind: ActionGroupKind) {
        let idx: Int
        if let firstSelected = rows.first(where: { selection.contains($0.id) }) {
            idx = firstSelected.group.eventIndices.first ?? recorder.events.count
        } else {
            idx = recorder.events.count
        }
        withUndo("Insert \(humanActionKindName(kind))") {
            switch kind {
            case .wait: recorder.insertWait(at: idx, milliseconds: insertWaitMs)
            case .click: recorder.insertClick(at: idx)
            case .drag: recorder.insertDrag(at: idx)
            case .keyPress: recorder.insertKeystroke(at: idx)
            default: break
            }
        }
    }

    private func applyStretch() {
        withUndo("Time Stretch") {
            recorder.scaleTime(by: stretchFactor)
        }
        stretchFactor = 1.0
    }

    private func shiftSelection(by delta: TimeInterval) {
        var allIndices: [Int] = []
        for groupID in selection {
            if let row = rows.first(where: { $0.id == groupID }) {
                allIndices.append(contentsOf: row.group.eventIndices)
            }
        }
        guard !allIndices.isEmpty else { return }
        withUndo("Shift Actions") {
            recorder.shiftTime(of: IndexSet(allIndices), by: delta)
        }
    }

    private func applyInspector() {
        guard selection.count == 1, let selectId = selection.first,
              let row = rows.first(where: { $0.id == selectId }) else { return }
        let grp = row.group
        
        withUndo("Edit Action") {
            if grp.kind == .wait {
                if let t = TimeInterval(inspTime) {
                    let oldDuration = grp.duration
                    let newDuration = max(0.0, t)
                    let delta = newDuration - oldDuration
                    
                    let startIndex = recorder.events.firstIndex(where: { $0.time >= grp.endTime }) ?? recorder.events.count
                    if startIndex == recorder.events.count {
                        recorder.setLiveDuration(recorder.liveDuration + delta)
                    } else {
                        let affectedIndices = IndexSet(startIndex..<recorder.events.count)
                        recorder.shiftTime(of: affectedIndices, by: delta)
                    }
                }
            } else {
                if let t = TimeInterval(inspTime) {
                    let delta = t - grp.startTime
                    recorder.shiftTime(of: IndexSet(grp.eventIndices), by: delta)
                }
            }
            
            if let sp = grp.startPoint {
                if let newX = Double(inspX), let newY = Double(inspY) {
                    let deltaStart = CGPoint(x: CGFloat(newX) - sp.x, y: CGFloat(newY) - sp.y)
                    
                    var deltaEnd = deltaStart
                    if grp.kind == .drag, let ep = grp.endPoint,
                       let newEndX = Double(inspEndX), let newEndY = Double(inspEndY) {
                        deltaEnd = CGPoint(x: CGFloat(newEndX) - ep.x, y: CGFloat(newEndY) - ep.y)
                    }
                    
                    recorder.translateEventsLinear(at: grp.eventIndices, startDelta: deltaStart, endDelta: deltaEnd)
                }
            }
            
            if (grp.kind == .keyPress || grp.kind == .keyHold), let k = UInt16(inspKey) {
                recorder.updateKeyStroke(at: grp.eventIndices, keyCode: k, flags: inspFlags)
            }
        }
        onLoadInspector()
        onUpdatePreview()
    }
}

// MARK: - Table

/// Fixed column widths shared by the events header + rows.
private enum EventCol {
    static let num: CGFloat = 38
    static let time: CGFloat = 84
    static let pos: CGFloat = 132
    static let key: CGFloat = 80
}

struct ActionRowDropDelegate: DropDelegate {
    let rowID: UUID
    @Binding var dragOverID: UUID?
    @Binding var draggedID: UUID?
    var onDrop: (UUID, UUID) -> Void
    
    func performDrop(info: DropInfo) -> Bool {
        if let src = draggedID {
            onDrop(src, rowID)
        }
        dragOverID = nil
        draggedID = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        dragOverID = rowID
    }
    
    func dropExited(info: DropInfo) {
        if dragOverID == rowID {
            dragOverID = nil
        }
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return draggedID != nil
    }
}

private struct ActionListView: View {
    @EnvironmentObject var library: MacroLibrary
    @EnvironmentObject var recorder: Recorder
    @Environment(\.undoManager) private var undoManager
    let rows: [ActionRow]
    @Binding var selection: Set<UUID>
    @State private var lastAnchor: UUID?
    @State private var dragOverID: UUID? = nil
    @State private var draggedID: UUID? = nil
    
    private let bottomDropID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(NSLocalizedString("ACTIONS", comment: ""))
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Text("\(rows.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                if !selection.isEmpty {
                    Text(String(format: NSLocalizedString("%d selected", comment: ""), selection.count))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Brand.accent(library.currentMacro?.accent))
                }
            }

            VStack(spacing: 0) {
                headerRow
                Divider().opacity(0.5)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            VStack(spacing: 0) {
                                if dragOverID == row.id {
                                    Rectangle()
                                        .fill(Color.accentColor)
                                        .frame(height: 2)
                                }
                                ActionRowView(
                                    row: row,
                                    order: index + 1,
                                    selected: selection.contains(row.id),
                                    onTap: { mods in handleTap(row.id, mods: mods) },
                                    draggedID: $draggedID
                                )
                                .onDrop(of: [.text], delegate: ActionRowDropDelegate(
                                    rowID: row.id,
                                    dragOverID: $dragOverID,
                                    draggedID: $draggedID,
                                    onDrop: { src, target in
                                        moveRows(sourceID: src, beforeTargetID: target)
                                    }
                                ))
                            }
                        }
                        
                        // Bottom drop zone
                        Color.clear
                            .frame(height: 24)
                            .contentShape(Rectangle())
                            .onDrop(of: [.text], delegate: ActionRowDropDelegate(
                                rowID: bottomDropID,
                                dragOverID: $dragOverID,
                                draggedID: $draggedID,
                                onDrop: { src, _ in
                                    moveRowsToEnd(sourceID: src)
                                }
                            ))
                            .overlay(
                                Group {
                                    if dragOverID == bottomDropID {
                                        Rectangle()
                                            .fill(Color.accentColor)
                                            .frame(height: 2)
                                            .frame(maxHeight: .infinity, alignment: .top)
                                    }
                                }
                            )
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, 12)
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("#").frame(width: EventCol.num, alignment: .center)
            Text(NSLocalizedString("TIME", comment: "")).frame(width: EventCol.time, alignment: .center)
            Text(NSLocalizedString("ACTION", comment: "")).frame(maxWidth: .infinity, alignment: .center)
            Text(NSLocalizedString("POSITION", comment: "")).frame(width: EventCol.pos, alignment: .center)
            Text(NSLocalizedString("KEY", comment: "")).frame(width: EventCol.key, alignment: .center)
        }
        .font(.system(size: 9.5, weight: .semibold))
        .tracking(0.6)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func withUndo(_ name: String, _ mutate: () -> Void) {
        let snapshot = recorder.events
        undoManager?.registerUndo(withTarget: recorder) { [weak undoManager] rec in
            let redoSnapshot = rec.events
            rec.loadEvents(snapshot)
            undoManager?.registerUndo(withTarget: rec) { rec2 in
                rec2.loadEvents(redoSnapshot)
            }
        }
        undoManager?.setActionName(name)
        mutate()
    }

    private func moveRows(sourceID: UUID, beforeTargetID: UUID) {
        let movingGroupIDs: Set<UUID>
        if selection.contains(sourceID) {
            movingGroupIDs = selection
        } else {
            movingGroupIDs = [sourceID]
        }
        
        let movingRows = rows.filter { movingGroupIDs.contains($0.id) }
        let sourceEventIndices = movingRows.flatMap { $0.group.eventIndices }
        guard !sourceEventIndices.isEmpty else { return }
        
        let targetRow = rows.first(where: { $0.id == beforeTargetID })
        let targetEventIndex = targetRow?.group.eventIndices.first
        
        let count = sourceEventIndices.count
        let adjTargetIndex: Int
        if let targetIdx = targetEventIndex {
            adjTargetIndex = targetIdx - sourceEventIndices.filter { $0 < targetIdx }.count
        } else {
            adjTargetIndex = recorder.events.count - count
        }
        let movedRange = adjTargetIndex ..< (adjTargetIndex + count)
        
        withUndo(NSLocalizedString("Move Action", comment: "")) {
            recorder.reorderGroup(sourceEventIndices: sourceEventIndices, beforeEventIndex: targetEventIndex)
        }
        
        DispatchQueue.main.async {
            let newRows = self.rows.filter { row in
                guard let firstIdx = row.group.eventIndices.first else { return false }
                return movedRange.contains(firstIdx)
            }
            if !newRows.isEmpty {
                self.selection = Set(newRows.map(\.id))
            }
        }
    }

    private func moveRowsToEnd(sourceID: UUID) {
        let movingGroupIDs: Set<UUID>
        if selection.contains(sourceID) {
            movingGroupIDs = selection
        } else {
            movingGroupIDs = [sourceID]
        }
        
        let movingRows = rows.filter { movingGroupIDs.contains($0.id) }
        let sourceEventIndices = movingRows.flatMap { $0.group.eventIndices }
        guard !sourceEventIndices.isEmpty else { return }
        
        let count = sourceEventIndices.count
        let adjTargetIndex = recorder.events.count - count
        let movedRange = adjTargetIndex ..< (adjTargetIndex + count)
        
        withUndo(NSLocalizedString("Move Action", comment: "")) {
            recorder.reorderGroup(sourceEventIndices: sourceEventIndices, beforeEventIndex: nil)
        }
        
        DispatchQueue.main.async {
            let newRows = self.rows.filter { row in
                guard let firstIdx = row.group.eventIndices.first else { return false }
                return movedRange.contains(firstIdx)
            }
            if !newRows.isEmpty {
                self.selection = Set(newRows.map(\.id))
            }
        }
    }

    private func handleTap(_ id: UUID, mods: NSEvent.ModifierFlags) {
        if mods.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            lastAnchor = id
        } else if mods.contains(.shift), let anchor = lastAnchor ?? selection.first,
                  let anchorIdx = rows.firstIndex(where: { $0.id == anchor }),
                  let targetIdx = rows.firstIndex(where: { $0.id == id }) {
            let lo = min(anchorIdx, targetIdx)
            let hi = max(anchorIdx, targetIdx)
            selection.formUnion(rows[lo...hi].map(\.id))
        } else {
            selection = [id]
            lastAnchor = id
        }
    }
}

private struct ActionRowView: View {
    @EnvironmentObject var library: MacroLibrary
    let row: ActionRow
    let order: Int
    let selected: Bool
    let onTap: (NSEvent.ModifierFlags) -> Void
    @Binding var draggedID: UUID?
    @State private var hovered = false

    private var g: ActionGroup { row.group }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                if hovered && row.group.kind != .wait {
                    Image(systemName: "line.horizontal.3")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .help(NSLocalizedString("Drag to reorder", comment: ""))
                } else {
                    Text(String(format: "%02d", order))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: EventCol.num, alignment: .center)
            .contentShape(Rectangle())
            .onDrag {
                draggedID = row.id
                return NSItemProvider(object: row.id.uuidString as NSString)
            }

            Text(String(format: "%.3fs", g.startTime))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: EventCol.time, alignment: .center)

            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(actionKindColor(g.kind).opacity(0.14))
                    Image(systemName: actionKindIcon(g.kind))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(actionKindColor(g.kind))
                }
                .frame(width: 20, height: 20)
                Text(g.summary)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                
                if g.eventIndices.count > 1 {
                    Text(String(format: NSLocalizedString("Merged (%d)", comment: ""), g.eventIndices.count))
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Brand.accent(library.currentMacro?.accent))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 0.5)
                        .background(
                            Capsule()
                                .fill(Brand.accent(library.currentMacro?.accent).opacity(0.12))
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Group {
                if let sp = g.startPoint {
                    if let ep = g.endPoint, g.kind == .drag {
                        Text("(\(Int(sp.x)),\(Int(sp.y)))→(\(Int(ep.x)),\(Int(ep.y)))")
                    } else {
                        Text("(\(Int(sp.x)), \(Int(sp.y)))")
                    }
                } else {
                    Text("—").foregroundStyle(.quaternary)
                }
            }
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: EventCol.pos, alignment: .center)

            Group {
                if (g.kind == .keyPress || g.kind == .keyHold), let kc = g.keyCode {
                    Text(shortcutName(keyCode: kc, flags: g.keyFlags ?? 0))
                } else {
                    Text("—").foregroundStyle(.quaternary)
                }
            }
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: EventCol.key, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            ZStack(alignment: .leading) {
                let accent = Brand.accent(library.currentMacro?.accent)
                Rectangle().fill(
                    selected ? accent.opacity(0.12)
                             : (hovered ? Color.primary.opacity(0.035) : Color.clear))
                if selected {
                    Rectangle().fill(accent).frame(width: 2)
                }
            }
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { onTap(NSApp.currentEvent?.modifierFlags ?? []) }
    }
}

// MARK: - Footer

private struct EditorFooter: View {
    let eventCount: Int
    let selectedCount: Int
    let duration: TimeInterval

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                Label(String(format: NSLocalizedString("%d events", comment: ""), eventCount), systemImage: "wave.3.right")
                Text("·").foregroundStyle(.tertiary)
                Label(formatDuration(duration), systemImage: "clock")
                if selectedCount > 0 {
                    Text("·").foregroundStyle(.tertiary)
                    Label(String(format: NSLocalizedString("%d selected", comment: ""), selectedCount), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
                Spacer()
                Text(NSLocalizedString("Edits apply live · use Save to persist", comment: ""))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
        }
        .background(VisualEffectBackground(material: .titlebar, blendingMode: .withinWindow))
    }
}

// MARK: - Helpers

func formatDuration(_ d: TimeInterval) -> String {
    let m = Int(d) / 60
    let s = Int(d) % 60
    let cs = Int((d - floor(d)) * 100)
    return String(format: "%02d:%02d.%02d", m, s, cs)
}

func humanKindName(_ k: RecordedEvent.Kind) -> String {
    switch k {
    case .leftMouseDown:     return NSLocalizedString("Left Click ↓", comment: "")
    case .leftMouseUp:       return NSLocalizedString("Left Click ↑", comment: "")
    case .rightMouseDown:    return NSLocalizedString("Right Click ↓", comment: "")
    case .rightMouseUp:      return NSLocalizedString("Right Click ↑", comment: "")
    case .mouseMoved:        return NSLocalizedString("Mouse Move", comment: "")
    case .leftMouseDragged:  return NSLocalizedString("Left Drag", comment: "")
    case .rightMouseDragged: return NSLocalizedString("Right Drag", comment: "")
    case .otherMouseDown:    return NSLocalizedString("Other Click ↓", comment: "")
    case .otherMouseUp:      return NSLocalizedString("Other Click ↑", comment: "")
    case .otherMouseDragged: return NSLocalizedString("Other Drag", comment: "")
    case .keyDown:           return NSLocalizedString("Key Down", comment: "")
    case .keyUp:             return NSLocalizedString("Key Up", comment: "")
    case .flagsChanged:      return NSLocalizedString("Modifier", comment: "")
    case .scrollWheel:       return NSLocalizedString("Scroll", comment: "")
    }
}

func kindIcon(_ k: RecordedEvent.Kind) -> String {
    if k.isKey { return "keyboard" }
    switch k {
    case .leftMouseDown, .leftMouseUp:           return "cursorarrow.click"
    case .rightMouseDown, .rightMouseUp:         return "cursorarrow.click.2"
    case .mouseMoved:                            return "arrow.up.left.and.arrow.down.right"
    case .leftMouseDragged, .rightMouseDragged,
         .otherMouseDragged:                     return "hand.draw"
    case .scrollWheel:                           return "arrow.up.and.down"
    case .otherMouseDown, .otherMouseUp:         return "circle.grid.cross"
    default:                                     return "circle"
    }
}

func actionKindColor(_ k: ActionGroupKind) -> Color {
    switch k {
    case .click, .doubleClick: return Brand.sigGreen
    case .longPress: return Brand.sigGreen
    case .drag: return Brand.sigViolet
    case .scroll: return Brand.sigTeal
    case .keyPress: return Brand.sigBlue
    case .keyHold: return Brand.sigBlue
    case .wait: return .secondary
    case .mouseMove: return .secondary
    }
}

func actionKindIcon(_ k: ActionGroupKind) -> String {
    switch k {
    case .click: return "cursorarrow.click"
    case .doubleClick: return "cursorarrow.click.2"
    case .longPress: return "hand.tap"
    case .drag: return "hand.draw"
    case .scroll: return "arrow.up.and.down"
    case .keyPress: return "keyboard"
    case .keyHold: return "keyboard"
    case .wait: return "clock"
    case .mouseMove: return "arrow.up.left.and.arrow.down.right"
    }
}

func humanActionKindName(_ k: ActionGroupKind) -> String {
    switch k {
    case .click: return NSLocalizedString("Click", comment: "")
    case .doubleClick: return NSLocalizedString("Double Click", comment: "")
    case .longPress: return NSLocalizedString("Long Press", comment: "")
    case .drag: return NSLocalizedString("Drag", comment: "")
    case .scroll: return NSLocalizedString("Scroll", comment: "")
    case .keyPress: return NSLocalizedString("KeyPress", comment: "")
    case .keyHold: return NSLocalizedString("KeyHold", comment: "")
    case .wait: return NSLocalizedString("Wait", comment: "")
    case .mouseMove: return NSLocalizedString("Mouse Move", comment: "")
    }
}

func kindColor(_ k: RecordedEvent.Kind) -> Color {
    Brand.eventColor(k)
}

/// Human-readable name for a small set of common Mac keycodes.
func keyName(_ code: UInt16) -> String? {
    let map: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
        38: "J", 40: "K",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
        26: "7", 28: "8", 25: "9", 29: "0",
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Escape",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        103: "F11", 109: "F10", 111: "F12", 122: "F1", 120: "F2",
        99: "F3", 118: "F4",
        55: "⌘", 56: "⇧", 58: "⌥", 59: "⌃",
    ]
    return map[code]
}

func modifierString(flags: UInt64) -> String {
    var parts: [String] = []
    let flagsVal = NSEvent.ModifierFlags(rawValue: UInt(flags))
    if flagsVal.contains(.control) { parts.append("⌃") }
    if flagsVal.contains(.option) { parts.append("⌥") }
    if flagsVal.contains(.shift) { parts.append("⇧") }
    if flagsVal.contains(.command) { parts.append("⌘") }
    return parts.joined()
}

func shortcutName(keyCode: UInt16, flags: UInt64) -> String {
    let mods = modifierString(flags: flags)
    let key = keyName(keyCode) ?? "\(keyCode)"
    return mods + key
}

// MARK: - On-Screen Coordinate Preview Overlay

struct PreviewAction: Identifiable {
    let id: UUID
    let kind: ActionGroupKind
    let selectedPoint: CGPoint?
    let dragPath: [CGPoint]
    let themeColor: Color
    let order: Int
}

struct RelativePreviewAction: Identifiable {
    let id: UUID
    let kind: ActionGroupKind
    let selectedPoint: CGPoint?
    let dragPath: [CGPoint]
    let themeColor: Color
    let order: Int
}

/// A borderless overlay panel that lets clicks pass through to apps below
/// EXCEPT when the mouse is over an interactive crosshair / drag-handle.
/// Uses a polling timer on NSEvent.mouseLocation to toggle ignoresMouseEvents,
/// which is the standard macOS pattern for click-through overlays.
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
        
        // ESC key listener (local — works when TinyTask is active)
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
        stopTracking()
    }
}

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
    
    private func configureTransparency(on layer: CALayer) {
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

private func screenToSwiftUI(_ pt: CGPoint, window: NSWindow, primaryScreenHeight: CGFloat) -> CGPoint {
    let cocoaScreenPt = NSPoint(x: pt.x, y: primaryScreenHeight - pt.y)
    let localPt = window.convertPoint(fromScreen: cocoaScreenPt)
    return CGPoint(
        x: localPt.x,
        y: (window.contentView?.bounds.height ?? window.frame.height) - localPt.y
    )
}

private func swiftuiToScreen(_ pt: CGPoint, window: NSWindow, primaryScreenHeight: CGFloat) -> CGPoint {
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
    
    func clearCallbacks() {
        onDragStarted = nil
        onDragStartPointEnded = nil
        onDragEndPointEnded = nil
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
                    if (action.kind == .drag || action.kind == .scroll),
                       action.dragPath.count > 1,
                       let endPt = action.dragPath.last {
                        let dx = sx - endPt.x, dy = sy - endPt.y
                        if dx * dx + dy * dy <= 784 { return true }
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

private extension CGSize {
    func clamped(to maxVal: CGFloat) -> CGSize {
        CGSize(
            width: max(min(width, maxVal), -maxVal),
            height: max(min(height, maxVal), -maxVal)
        )
    }
}

private struct ActiveDragEdit {
    var actionID: UUID
    var handle: DragHandle
    var translation: CGSize
    
    var clampedTranslation: CGSize {
        translation.clamped(to: 800)
    }
}

private enum DragHandle {
    case start
    case end
}

private extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGSize) -> CGPoint {
        CGPoint(x: lhs.x + rhs.width, y: lhs.y + rhs.height)
    }
}

struct TargetCrosshairView: View {
    @ObservedObject var state: OverlayState
    
    @State private var pulseScale: CGFloat = 0.8
    @State private var pulseOpacity: Double = 0.8
    @State private var lineDashPhase: CGFloat = 0
    
    @State private var activeDrag: ActiveDragEdit?
    @State private var confirmFlashActionID: UUID?
    @State private var confirmFlash: Bool = false
    @State private var flashPoint: CGPoint? = nil
    @State private var hoveredActionID: UUID?
    @State private var hoveredHandle: DragHandle?
    
    private var actions: [RelativePreviewAction] { state.actions }
    
    private func getDisplayStartPoint(for action: RelativePreviewAction) -> CGPoint? {
        guard let pt = action.selectedPoint else { return nil }
        if let drag = activeDrag, drag.actionID == action.id {
            switch drag.handle {
            case .start:
                return pt + drag.clampedTranslation
            default:
                return pt
            }
        }
        return pt
    }
    
    private func getDisplayEndPoint(for action: RelativePreviewAction) -> CGPoint? {
        guard let endPt = action.dragPath.last else { return action.selectedPoint }
        if let drag = activeDrag, drag.actionID == action.id {
            switch drag.handle {
            case .start, .end:
                return endPt + drag.clampedTranslation
            }
        }
        return endPt
    }
    
    private func getDisplayPath(for action: RelativePreviewAction) -> [CGPoint] {
        guard action.dragPath.count > 1 else { return [] }
        if let drag = activeDrag, drag.actionID == action.id {
            switch drag.handle {
            case .start:
                return action.dragPath.map { $0 + drag.clampedTranslation }
            case .end:
                if let start = action.selectedPoint ?? action.dragPath.first, let end = action.dragPath.last {
                    let newEnd = end + drag.clampedTranslation
                    return action.dragPath.map { conformPathPoint(pt: $0, start: start, oldEnd: end, newEnd: newEnd) }
                }
            }
        }
        return action.dragPath
    }
    
    private func conformPathPoint(pt: CGPoint, start: CGPoint, oldEnd: CGPoint, newEnd: CGPoint) -> CGPoint {
        let mainVector = CGPoint(x: oldEnd.x - start.x, y: oldEnd.y - start.y)
        let newVector = CGPoint(x: newEnd.x - start.x, y: newEnd.y - start.y)
        
        let oldLen2 = mainVector.x * mainVector.x + mainVector.y * mainVector.y
        guard oldLen2 > 0.001 else {
            let dx = newEnd.x - oldEnd.x
            let dy = newEnd.y - oldEnd.y
            return CGPoint(x: pt.x + dx, y: pt.y + dy)
        }
        
        let mainVectorPerp = CGPoint(x: -mainVector.y, y: mainVector.x)
        let newVectorPerp = CGPoint(x: -newVector.y, y: newVector.x)
        
        let dx = pt.x - start.x
        let dy = pt.y - start.y
        
        let u = (dx * mainVector.x + dy * mainVector.y) / oldLen2
        let v = (dx * mainVectorPerp.x + dy * mainVectorPerp.y) / oldLen2
        
        return CGPoint(
            x: start.x + u * newVector.x + v * newVectorPerp.x,
            y: start.y + u * newVector.y + v * newVectorPerp.y
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // 1. Connection dashed path in sequential order
                Path { path in
                var lastPt: CGPoint? = nil
                for action in actions {
                    let startPt = getDisplayStartPoint(for: action)
                    if let start = startPt {
                        if let last = lastPt {
                            path.move(to: last)
                            path.addLine(to: start)
                        }
                        lastPt = getDisplayEndPoint(for: action)
                    }
                }
            }
            .stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [4, 4]))
            
            // 2. Ripple animation overlay
            if let fPt = flashPoint {
                Circle()
                    .stroke(Color.green.opacity(confirmFlash ? 0.8 : 0.0), lineWidth: 2)
                    .frame(width: confirmFlash ? 16 : 48, height: confirmFlash ? 16 : 48)
                    .position(fPt)
            }
            
            // 3. Render each action's markers
            ForEach(actions) { action in
                // Drag path
                let displayPath = getDisplayPath(for: action)
                if (action.kind == .drag || action.kind == .scroll), displayPath.count > 1 {
                    Path { path in
                        path.addLines(displayPath)
                    }
                    .stroke(Color.black.opacity(0.3), lineWidth: 3.5)
                    
                    Path { path in
                        path.addLines(displayPath)
                    }
                    .stroke(
                        action.themeColor,
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round, miterLimit: 10, dash: [6, 4], dashPhase: lineDashPhase)
                    )
                    
                    if let startPt = displayPath.first {
                        Circle()
                            .fill(action.themeColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: .black.opacity(0.3), radius: 2)
                            .position(startPt)
                    }
                    
                    if let endPt = displayPath.last {
                        let showArrow: Bool = {
                            if let startPt = getDisplayStartPoint(for: action) {
                                let dx = endPt.x - startPt.x
                                let dy = endPt.y - startPt.y
                                return (dx * dx + dy * dy) > 225
                            }
                            return true
                        }()
                        
                        if showArrow, let displayEndPt = getDisplayEndPoint(for: action) {
                            let isCurrentDrag = (activeDrag?.actionID == action.id && activeDrag?.handle == .end)
                            
                            Image(systemName: "arrowtriangle.down.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                                .foregroundStyle(action.themeColor)
                                .shadow(color: .black.opacity(0.3), radius: 2)
                                .rotationEffect(arrowRotation(for: displayPath))
                                .scaleEffect(isCurrentDrag ? 1.25 : 1.0)
                                .overlay(
                                    Group {
                                        if isCurrentDrag, activeDrag != nil {
                                            let screenPt = {
                                                if let win = state.window {
                                                    return swiftuiToScreen(displayEndPt, window: win, primaryScreenHeight: state.primaryScreenHeight)
                                                }
                                                return displayEndPt
                                            }()
                                            
                                            Text("(\(Int(screenPt.x.rounded()).formatted(.number)), \(Int(screenPt.y.rounded()).formatted(.number)))")
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Color.black.opacity(0.8))
                                                .clipShape(.rect(cornerRadius: 5))
                                                .offset(y: -36)
                                                .fixedSize()
                                        }
                                    }
                                )
                                .help(NSLocalizedString("Drag to adjust swipe destination (rotate/stretch)", comment: ""))
                                .frame(width: 100, height: 100) // Large frame to prevent visual clipping of badge/arrow/shadows
                                .contentShape(Rectangle())
                                .offset(x: displayEndPt.x - 50, y: displayEndPt.y - 50)
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            if activeDrag == nil {
                                                activeDrag = ActiveDragEdit(actionID: action.id, handle: .end, translation: value.translation)
                                                CoordinatePreviewOverlay.shared.onDragStarted?(action.id)
                                            } else {
                                                activeDrag?.translation = value.translation
                                            }
                                        }
                                        .onEnded { value in
                                            let finalTranslation = value.translation.clamped(to: 800)
                                            activeDrag = nil
                                            
                                            let distance = hypot(finalTranslation.width, finalTranslation.height)
                                            guard distance >= 0.5 else { return }
                                            
                                            CoordinatePreviewOverlay.shared.onDragEndPointEnded?(action.id, finalTranslation.width, finalTranslation.height)
                                            
                                            // Trigger ripple
                                            flashPoint = endPt + finalTranslation
                                            confirmFlashActionID = action.id
                                            confirmFlash = true
                                            withAnimation(.easeOut(duration: 0.6)) {
                                                confirmFlash = false
                                            }
                                        }
                                )
                        }
                    }
                }
                
                // Targets
                if let pt = action.selectedPoint, let displayPt = getDisplayStartPoint(for: action) {
                    let isCurrentDrag = (activeDrag?.actionID == action.id && activeDrag?.handle == .start)
                    
                    ZStack {
                        // Current Drag Tooltip
                        if isCurrentDrag, activeDrag != nil {
                            let screenPt = {
                                if let win = state.window {
                                    return swiftuiToScreen(displayPt, window: win, primaryScreenHeight: state.primaryScreenHeight)
                                }
                                return displayPt
                            }()
                            
                            Text("(\(Int(screenPt.x.rounded()).formatted(.number)), \(Int(screenPt.y.rounded()).formatted(.number)))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.8))
                                .clipShape(.rect(cornerRadius: 5))
                                .offset(y: -36)
                                .fixedSize()
                        }
                        
                        Circle()
                            .stroke(action.themeColor.opacity(0.8), lineWidth: 1.5)
                            .frame(width: 24, height: 24)
                            .scaleEffect(isCurrentDrag ? 1.25 : pulseScale)
                            .opacity(isCurrentDrag ? 0.3 : pulseOpacity)
                        
                        Circle()
                            .stroke(action.themeColor, lineWidth: 1.5)
                            .frame(width: 12, height: 12)
                        
                        Circle()
                            .fill(action.themeColor)
                            .frame(width: 3.5, height: 3.5)
                        
                        Rectangle()
                            .fill(action.themeColor.opacity(0.6))
                            .frame(width: 16, height: 1)
                        Rectangle()
                            .fill(action.themeColor.opacity(0.6))
                            .frame(width: 1, height: 16)
                    }
                    .scaleEffect(isCurrentDrag ? 1.15 : 1.0)
                    .background(
                        // Sequential Order Badge
                        Text("\(action.order)")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 0.5)
                            .background(
                                Capsule()
                                    .fill(action.themeColor)
                                    .shadow(color: .black.opacity(0.2), radius: 1)
                            )
                            .offset(x: 14, y: -14)
                    )
                    .help(NSLocalizedString("Drag to move entire path", comment: ""))
                    .frame(width: 100, height: 100) // Large frame to prevent visual clipping of badge/arrow/shadows
                    .contentShape(Rectangle())
                    .offset(x: displayPt.x - 50, y: displayPt.y - 50)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if activeDrag == nil {
                                    activeDrag = ActiveDragEdit(actionID: action.id, handle: .start, translation: value.translation)
                                    CoordinatePreviewOverlay.shared.onDragStarted?(action.id)
                                } else {
                                    activeDrag?.translation = value.translation
                                }
                             }
                            .onEnded { value in
                                let finalTranslation = value.translation.clamped(to: 800)
                                activeDrag = nil
                                
                                let distance = hypot(finalTranslation.width, finalTranslation.height)
                                guard distance >= 0.5 else { return }
                                
                                CoordinatePreviewOverlay.shared.onDragStartPointEnded?(action.id, finalTranslation.width, finalTranslation.height)
                                
                                // Trigger ripple
                                flashPoint = pt + finalTranslation
                                confirmFlashActionID = action.id
                                confirmFlash = true
                                withAnimation(.easeOut(duration: 0.6)) {
                                    confirmFlash = false
                                }
                            }
                    )
                }
            }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseScale = 1.2
                pulseOpacity = 0.2
            }
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                lineDashPhase = -10
            }
        }
        .onDisappear {
            activeDrag = nil
        }
        .onChange(of: actions.map(\.id)) {
            activeDrag = nil
        }
        .transaction { transaction in
            if activeDrag != nil {
                transaction.animation = nil
            }
        }
    }
    
    private func arrowRotation(for path: [CGPoint]) -> Angle {
        guard path.count >= 2 else { return .zero }
        let p1 = path[path.count - 2]
        let p2 = path[path.count - 1]
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let angle = atan2(dy, dx)
        return Angle(radians: Double(angle) - .pi / 2)
    }
}

// MARK: - Screen Coordinate Picker Overlay

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

/// Simple instruction label displayed during coordinate picking
private struct PickerInstructionView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "scope")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Double-click anywhere to pick coordinate", comment: ""))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text(NSLocalizedString("Press ESC to cancel", comment: ""))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
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

