import Cocoa
import SwiftUI
import Combine
import SparkleRecorderCore
import UniformTypeIdentifiers

// MARK: - Window controller

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    var shouldClose: (() -> Bool)?
    var onClose: (() -> Void)?

    init<V: View>(rootView: V, title: String = String(localized: "Macro Editor", table: "EditorUX")) {
        let host = NSHostingController(rootView: rootView)
        let win = NSWindow(contentViewController: host)
        win.title = title
        win.setContentSize(NSSize(width: 1200, height: 800))
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        win.minSize = NSSize(width: 860, height: 620)
        win.isReleasedWhenClosed = false
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .visible
        win.isMovableByWindowBackground = false
        win.backgroundColor = .clear
        super.init(window: win)
        win.delegate = self
        
        if !win.setFrameUsingName("SparkleRecorder.MacroEditor") {
            win.center()
        }
        win.setFrameAutosaveName("SparkleRecorder.MacroEditor")
    }
    required init?(coder: NSCoder) { fatalError() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        shouldClose?() ?? true
    }

    func windowWillClose(_ notification: Notification) {
        CoordinatePreviewOverlay.shared.hide()
        onClose?()
    }
}


// MARK: - Row model

struct DragEditSession {
    let groupID: UUID
    let group: ActionGroup
    let eventIndices: [Int]
    let snapshot: [RecordedEvent]
    let liveDuration: TimeInterval
}

// MARK: - Editor view

struct CandidateEditorContainer: View {
    let controller: MenuBarController
    @ObservedObject var session: MacroCandidateEditorSession

    var body: some View {
        EditorView(controller: controller, candidateSession: session)
    }
}

struct EditorView: View {
    let controller: MenuBarController
    let candidateSession: MacroCandidateEditorSession?
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
    @State private var inspStrategy: CoordinateStrategy = .windowLocalPreferred
    @State private var inspOCRText: String = ""
    @State private var inspFallbackPolicy: LocatorFallbackPolicy = .fail
    @State private var inspTimeout: Double = 10.0
    @State private var inspVerifyMustExist: Bool = true
    @State private var inspBehaviorName: String = ""
    @State private var activeDragSession: DragEditSession? = nil
    @State private var hoveredRow: UUID? = nil
    @State private var smartMergeGestures = true
    @AppStorage("showOverlayPreview") var showOverlayPreview = true

    @State private var cachedRows: [ActionRow] = []
    @State private var cachedTimelineSamples: [TimelineSampledEvent] = []
    @State private var repeatUntilDraftPreviewState: AutomationWorkflowDraftPreviewState?
    @State private var repeatUntilDraftAlertTitle = ""
    @State private var repeatUntilDraftAlertMessage = ""
    @State private var isShowingRepeatUntilDraftAlert = false

    init(controller: MenuBarController, candidateSession: MacroCandidateEditorSession? = nil) {
        self.controller = controller
        self.candidateSession = candidateSession
    }

    var rows: [ActionRow] { cachedRows }
    var editingMacro: SavedMacro? { candidateSession?.draftMacro ?? library.currentMacro }
    var isEditingCandidate: Bool { candidateSession != nil }

    @discardableResult
    func updateCachedRows() -> [ActionRow] {
        let selectedGroups = cachedRows.filter { selection.contains($0.id) }.map { $0.group }
        let selectedIndices = selectedGroups.compactMap { $0.eventIndices.first }
        let selectedWaits = selectedGroups.filter { $0.kind.isPassiveWait }.map { $0.endTime }

        let list = ActionGroupProjection.groups(
            from: recorder.events,
            liveDuration: recorder.liveDuration,
            hidesMouseMoves: hideMouseMoves,
            smartMergeGestures: smartMergeGestures
        ).map { group in
            ActionRow(group: group)
        }
        cachedRows = list
        cachedTimelineSamples = TimelineProjection.sampleEvents(from: recorder.events)

        var newSelection = Set<UUID>()
        for row in list {
            if row.group.kind.isPassiveWait {
                if selectedWaits.contains(where: { abs($0 - row.group.endTime) < 0.01 }) {
                    newSelection.insert(row.id)
                }
            } else if let firstIdx = row.group.eventIndices.first, selectedIndices.contains(firstIdx) {
                newSelection.insert(row.id)
            }
        }
        
        if newSelection != selection {
            DispatchQueue.main.async {
                self.selection = newSelection
            }
        }

        updatePreview()
        return list
    }

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .windowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            PlayerStateListener()

            VStack(spacing: 0) {
                if let candidateSession {
                    candidateEditorBanner(candidateSession)
                    Divider().opacity(0.45)
                }

                EditorToolbar(
                    macro: editingMacro,
                    rowCount: recorder.events.count,
                    duration: recorder.events.last?.time ?? 0,
                    health: macroEditorHealthSummary(for: rows.map(\.group), events: recorder.events),
                    hideMouseMoves: $hideMouseMoves,
                    showAllPaths: $showAllPaths,
                    showOverlayPreview: $showOverlayPreview,
                    smartMergeGestures: $smartMergeGestures,
                    onExport: isEditingCandidate ? nil : { controller.exportAsScript() }
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
                        inspStrategy: $inspStrategy,
                        inspOCRText: $inspOCRText,
                        inspFallbackPolicy: $inspFallbackPolicy,
                        inspTimeout: $inspTimeout,
                        inspVerifyMustExist: $inspVerifyMustExist,
                        inspBehaviorName: $inspBehaviorName,
                        recorder: recorder,
                        macroID: editingMacro?.id,
                        surfaces: editingMacro?.surfaces ?? [:],
                        followWindowOffset: editingMacro?.followWindowOffset ?? true,
                        canEditFollowWindowOffset: !isEditingCandidate,
                        allowsLibrarySideEffects: !isEditingCandidate,
                        onChooseTargetWindow: { surfaceID in
                            if let candidateSession {
                                controller.chooseTargetWindow(for: candidateSession, surfaceID: surfaceID)
                            } else if let id = library.currentMacro?.id {
                                controller.chooseTargetWindow(for: id, surfaceID: surfaceID)
                            }
                        },
                        onRemoveTargetWindow: { surfaceID in
                            if let candidateSession {
                                _ = candidateSession.removeSurface(surfaceID)
                            } else if let id = library.currentMacro?.id {
                                controller.removeTargetWindow(for: id, surfaceID: surfaceID)
                            }
                        },
                        onSetFollowWindowOffset: { enabled in
                            guard !isEditingCandidate, let id = library.currentMacro?.id else { return }
                            library.setFollowWindowOffset(id: id, enabled: enabled)
                        },
                        onLoadInspector: loadInspector,
                        onUpdatePreview: updatePreview,
                        onPickCoordinate: { isEndPoint in
                            self.startPickingCoordinate(isEndPoint: isEndPoint)
                        },
                        onAddClickPoint: {
                            self.startPickingAdditionalClickPoint()
                        },
                        onPickText: {
                            self.startPickingText()
                        },
                        onRefreshRows: updateCachedRows,
                        onCreateRepeatUntilDraft: { attempts, timeout, polling, policy in
                            createRepeatUntilDraftFromSelection(maxAttempts: attempts, timeoutSeconds: timeout, pollingSeconds: polling, failurePolicy: policy)
                        }
                    )
                    .frame(minWidth: 280, idealWidth: 310, maxWidth: 360)

                    VStack(spacing: 0) {
                        EditorTimeline(
                            samples: cachedTimelineSamples,
                            totalDuration: recorder.events.last?.time ?? 0,
                            groups: rows.map(\.group),
                            selection: $selection
                        )
                        .padding(14)

                        ActionListView(
                            rows: rows,
                            selection: $selection,
                            onRefreshRows: updateCachedRows,
                            toggleDisabledState: toggleDisabledState(for:),
                            playFromHere: playFromHere(anchor:),
                            playThisActionOnly: playThisActionOnly(anchor:)
                        )
                    }
                    .frame(minWidth: 420)
                }

                EditorFooter(eventCount: recorder.events.count,
                             selectedCount: selection.count,
                             duration: recorder.events.last?.time ?? 0,
                             health: macroEditorHealthSummary(for: rows.map(\.group), events: recorder.events))
            }
        }
        .disabled(state.appInteractionLocked)
        .frame(minWidth: 820, minHeight: 580)
        .onAppear {
            updateCachedRows()
        }
        .onChange(of: selection) {
            loadInspector()
            updatePreview()
        }
        .onChange(of: recorder.events) {
            guard !recorder.isRecording else { return }
            updateCachedRows()
            persistEditingEvents()
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
            guard !isEditingCandidate else { return }
            selection.removeAll()
            CoordinatePreviewOverlay.shared.hide()
            updateCachedRows()
        }
        .onDisappear {
            persistEditingEvents()
            CoordinatePreviewOverlay.shared.hide()
        }
        .sheet(item: $repeatUntilDraftPreviewState) { previewState in
            AutomationWorkflowDraftPreviewSheet(
                state: previewState,
                existingWorkflowName: nil,
                onImportWorkflow: { _, _ in
                    showRepeatUntilDraftAlert(
                        title: String(localized: "Open Workflow to import", table: "Automation"),
                        message: String(localized: "Repeat-Until drafts from Macro Editor stay in preview until structured loop runtime support lands.", table: "Automation")
                    )
                }
            )
        }
        .alert(repeatUntilDraftAlertTitle, isPresented: $isShowingRepeatUntilDraftAlert) {
            Button(String(localized: "OK", table: "Common"), role: .cancel) {}
        } message: {
            Text(repeatUntilDraftAlertMessage)
        }
    }

    @ViewBuilder
    func candidateEditorBanner(_ session: MacroCandidateEditorSession) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Editing candidate draft", tableName: "EditorUX")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Changes stay separate from the accepted macro. Saving creates a new candidate that must be tested again.", tableName: "EditorUX")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Editor previews help you adjust the draft. Return to Review and use Test once to qualify the saved candidate for acceptance.", tableName: "EditorUX")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button(String(localized: "Close", table: "Common")) {
                    controller.closeCandidateEditor()
                }
                .disabled(session.isSaving)

                Button {
                    persistEditingEvents()
                    Task {
                        if await session.save() {
                            controller.closeCandidateEditor()
                        }
                    }
                } label: {
                    if session.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            session.hasChanges
                                ? String(localized: "Save as new candidate", table: "EditorUX")
                                : String(localized: "Back to review", table: "EditorUX"),
                            systemImage: session.hasChanges ? "square.and.arrow.down" : "arrow.uturn.backward"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isSaving)
            }

            if let error = session.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !session.statusMessage.isEmpty {
                Text(session.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.055))
    }

    func persistEditingEvents() {
        if let candidateSession {
            candidateSession.updateEvents(recorder.events)
        } else {
            controller.persistEdits()
        }
    }

    func loadInspector() {
        if selection.count == 1, let groupID = selection.first,
           let row = rows.first(where: { $0.id == groupID }) {
            let grp = row.group
            if grp.kind.isPassiveWait {
                inspTime = formatInspectorTime(grp.duration)
            } else {
                inspTime = formatInspectorTime(grp.startTime)
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
            
            if let firstIdx = grp.eventIndices.first {
                let ev = recorder.events[firstIdx]
                inspStrategy = ev.coordinateStrategy ?? .windowLocalPreferred
                inspOCRText = ev.textAnchor?.text ?? ""
                inspFallbackPolicy = ev.locatorFallbackPolicy ?? .fail
                inspTimeout = ev.textTimeout ?? 10.0
                inspVerifyMustExist = ev.verifyMustExist ?? true
                inspBehaviorName = grp.behaviorGroupName ?? ev.behaviorGroupName ?? ""
            } else {
                inspStrategy = .windowLocalPreferred
                inspOCRText = ""
                inspFallbackPolicy = .fail
                inspTimeout = 10.0
                inspVerifyMustExist = true
                inspBehaviorName = grp.behaviorGroupName ?? ""
            }
        } else if selection.count > 1 {
            let textRows = textTargetRowsForCurrentSelection()
            var firstTextEvent: RecordedEvent?
            var firstBehaviorName: String?
            for row in textRows where firstTextEvent == nil {
                for index in row.group.eventIndices where recorder.events.indices.contains(index) {
                    let event = recorder.events[index]
                    if event.textAnchor != nil || event.coordinateStrategy == .locatorOnly {
                        firstTextEvent = event
                        break
                    }
                }
            }
            for row in rows where selection.contains(row.id) && firstBehaviorName == nil {
                firstBehaviorName = row.group.behaviorGroupName
                if firstBehaviorName == nil {
                    for index in row.group.eventIndices where recorder.events.indices.contains(index) {
                        if let name = recorder.events[index].behaviorGroupName {
                            firstBehaviorName = name
                            break
                        }
                    }
                }
            }

            inspTime = ""; inspX = ""; inspY = ""; inspEndX = ""; inspEndY = ""; inspKey = ""; inspFlags = 0
            inspStrategy = .locatorOnly
            inspOCRText = firstTextEvent?.textAnchor?.text ?? ""
            inspFallbackPolicy = firstTextEvent?.locatorFallbackPolicy ?? .fail
            inspTimeout = firstTextEvent?.textTimeout ?? 10.0
            inspVerifyMustExist = firstTextEvent?.verifyMustExist ?? true
            inspBehaviorName = firstBehaviorName ?? ""
        } else {
            inspTime = ""; inspX = ""; inspY = ""; inspEndX = ""; inspEndY = ""; inspKey = ""; inspFlags = 0
            inspStrategy = .windowLocalPreferred
            inspOCRText = ""
            inspFallbackPolicy = .fail
            inspTimeout = 10.0
            inspVerifyMustExist = true
            inspBehaviorName = ""
        }
    }

    func updatePreview() {
        guard showOverlayPreview else {
            CoordinatePreviewOverlay.shared.hide()
            return
        }
        
        let groupsToScan: [(id: UUID, grp: ActionGroup)]
        if showAllPaths {
            groupsToScan = rows.map { ($0.id, $0.group) }
        } else {
            groupsToScan = rows.compactMap { row in
                guard selection.contains(row.id) else { return nil }
                return (row.id, row.group)
            }
        }
        
        let currentMacro = editingMacro
        let events = recorder.events
        
        var actionsToPreview: [PreviewAction] = []
        
        // Build a temporary PlaybackContext to resolve coordinates
        var context = PlaybackContext()
        if let macro = currentMacro {
            context.surfaces = macro.surfaces
            context.coordinateMode = macro.followWindowOffset ? .boundWindowOffset : .screenAbsolute
            
            let tracker = WindowTracker()
            context.currentSurfaceFrames = tracker.resolveCurrentFrames(for: macro.surfaces)
            for (surfaceId, frame) in context.currentSurfaceFrames {
                if let surface = macro.surfaces[surfaceId] {
                    let contentFrame = estimatedContentFrame(for: surface, currentFrame: frame)
                    context.currentContentFrames[surfaceId] = contentFrame
                    context.currentTitleBarHeights[surfaceId] = max(0, contentFrame.y - frame.y)
                }
            }
        }
        
        let resolver = PointResolver()
        
        for (orderIdx, item) in groupsToScan.enumerated() {
            let grp = item.grp
            
            // Resolve startPoint
            var startPt: CGPoint? = nil
            var observedFrame: CGRect? = nil
            var searchRegion: CGRect? = nil
            var fallbackPoint: CGPoint? = nil
            var usesTextLocator = grp.textAnchor != nil
            if let firstIdx = grp.eventIndices.first, events.indices.contains(firstIdx) {
                let ev = events[firstIdx]
                usesTextLocator = usesTextLocator || ev.coordinateStrategy == .locatorOnly || ev.textAnchor != nil
                startPt = try? resolver.resolve(ev, context: context).get()
                if let anchor = ev.textAnchor {
                    let surfaceId = (try? MacroPlaybackSurfaceEditing.effectiveSurfaceID(
                        in: events,
                        eventIndices: grp.eventIndices,
                        surfaces: currentMacro?.surfaces ?? [:]
                    )) ?? nil
                    let contentFrame = surfaceId.flatMap { context.currentContentFrames[$0] }
                    let currentWindowFrame = surfaceId.flatMap { context.currentSurfaceFrames[$0] }
                    let recordedWindowFrame = surfaceId.flatMap { currentMacro?.surfaces[$0]?.recordedFrame }
                    let geometry: ResolvedTextAnchorGeometry
                    if let recordedWindowFrame, let currentWindowFrame {
                        geometry = TextAnchorGeometryProjection.resolve(
                            anchor,
                            contentFrame: contentFrame,
                            recordedWindowFrame: recordedWindowFrame,
                            currentWindowFrame: currentWindowFrame
                        )
                    } else {
                        geometry = TextAnchorGeometryProjection.resolve(anchor, contentFrame: contentFrame)
                    }
                    observedFrame = geometry.observedFrame.map {
                        CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
                    }
                    searchRegion = geometry.searchRegion.map {
                        CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
                    }
                    fallbackPoint = geometry.coordinateFallback.map { CGPoint(x: $0.x, y: $0.y) }
                    startPt = startPt ?? fallbackPoint ?? observedFrame.map { CGPoint(x: $0.midX, y: $0.midY) }
                }
            }
            
            // Resolve path
            var resolvedPath: [CGPoint] = []
            for idx in grp.eventIndices {
                if events.indices.contains(idx) {
                    let ev = events[idx]
                    if grp.kind.previewsPointSequence && ev.kind != .leftMouseDown && ev.kind != .rightMouseDown && ev.kind != .otherMouseDown {
                        continue
                    }
                    if let pt = try? resolver.resolve(ev, context: context).get() {
                        resolvedPath.append(pt)
                    }
                }
            }

            if grp.kind.editsSemanticTextTarget {
                searchRegion = searchRegion ?? observedFrame
                observedFrame = nil
                fallbackPoint = nil
                startPt = nil
            }
            
            if grp.kind.isPassiveWait || (grp.kind == .mouseMove && hideMouseMoves) {
                continue
            }
            
            actionsToPreview.append(PreviewAction(
                id: item.id,
                kind: grp.kind,
                affordance: ActionGroupProjection.previewAffordance(for: grp.kind, usesTextLocator: usesTextLocator),
                selectedPoint: startPt,
                dragPath: resolvedPath,
                observedFrame: observedFrame,
                searchRegion: searchRegion,
                fallbackPoint: fallbackPoint,
                themeColor: actionKindColor(grp.kind),
                order: orderIdx + 1
            ))
        }
        
        if !actionsToPreview.isEmpty {
            CoordinatePreviewOverlay.shared.onDragStarted = { [weak recorder] groupID in
                guard let rec = recorder else { return }
                if let grp = self.rows.first(where: { $0.id == groupID })?.group {
                    self.activeDragSession = DragEditSession(
                        groupID: groupID,
                        group: grp,
                        eventIndices: grp.eventIndices,
                        snapshot: rec.events,
                        liveDuration: rec.liveDuration
                    )
                }
            }
            CoordinatePreviewOverlay.shared.onDragStartPointEnded = { [weak recorder] groupID, dx, dy in
                guard let session = self.activeDragSession, session.groupID == groupID, let rec = recorder else { return }
                rec.loadEvents(session.snapshot, duration: session.liveDuration)
                self.activeDragSession = nil
                self.withUndo(String(localized: "Adjust Drag Start", table: "EditorUX")) {
                    if let start = session.group.startPoint,
                       let end = session.group.endPoint {
                        let newStart = CGPoint(x: start.x + dx, y: start.y + dy)
                        rec.events.conformPath(
                            at: session.eventIndices,
                            oldStartPoint: start,
                            oldEndPoint: end,
                            newStartPoint: newStart,
                            newEndPoint: end,
                            surfaces: currentMacro?.surfaces ?? [:]
                        )
                    }
                }
                self.updateCachedRows()
                self.loadInspector()
            }
            CoordinatePreviewOverlay.shared.onDragEndPointEnded = { [weak recorder] groupID, dx, dy in
                guard let session = self.activeDragSession, session.groupID == groupID, let rec = recorder else { return }
                rec.loadEvents(session.snapshot, duration: session.liveDuration)
                self.activeDragSession = nil
                self.withUndo(String(localized: "Adjust Swipe Destination", table: "Common")) {
                    if let start = session.group.startPoint,
                       let end = session.group.endPoint {
                        let newEnd = CGPoint(x: end.x + dx, y: end.y + dy)
                        rec.events.conformPath(at: session.eventIndices, startPoint: start, oldEndPoint: end, newEndPoint: newEnd, surfaces: currentMacro?.surfaces ?? [:])
                    }
                }
                self.updateCachedRows()
                self.loadInspector()
            }
            CoordinatePreviewOverlay.shared.onDragPathEnded = { [weak recorder] groupID, dx, dy in
                guard let session = self.activeDragSession, session.groupID == groupID, let rec = recorder else { return }
                rec.loadEvents(session.snapshot, duration: session.liveDuration)
                self.activeDragSession = nil
                let undoName = session.group.kind.previewsPointSequence
                    ? String(localized: "Move Click Points", table: "EditorUX")
                    : String(localized: "Move Drag Path", table: "EditorUX")
                self.withUndo(undoName) {
                    rec.events.translateEvents(at: session.eventIndices, dx: dx, dy: dy, surfaces: currentMacro?.surfaces ?? [:])
                }
                self.updateCachedRows()
                self.loadInspector()
            }
            CoordinatePreviewOverlay.shared.onDragPathPointEnded = { [weak recorder] groupID, pointIndex, dx, dy in
                guard let session = self.activeDragSession, session.groupID == groupID, let rec = recorder else { return }
                rec.loadEvents(session.snapshot, duration: session.liveDuration)
                self.activeDragSession = nil
                self.withUndo(String(localized: "Move Click Point", table: "EditorUX")) {
                    rec.events.translateMultiPointClickPoint(
                        at: session.eventIndices,
                        pointIndex: pointIndex,
                        dx: dx,
                        dy: dy,
                        surfaces: currentMacro?.surfaces ?? [:]
                    )
                }
                self.updateCachedRows()
                self.loadInspector()
            }
            CoordinatePreviewOverlay.shared.show(actions: actionsToPreview, selectedActionID: selection.count == 1 ? selection.first : nil)
        } else {
            CoordinatePreviewOverlay.shared.hide()
        }
    }
    
    func estimatedContentFrame(for surface: PlaybackSurface, currentFrame: RectValue) -> RectValue {
        guard let recordedContent = surface.recordedContentFrame else {
            let fallbackTop: CGFloat = surface.contentFrameSource == CoordinateMapper.ResolvedContentFrame.Source.fallbackOuterFrame.rawValue ? 0 : 28
            return RectValue(
                x: currentFrame.x,
                y: currentFrame.y + fallbackTop,
                width: currentFrame.width,
                height: max(1, currentFrame.height - fallbackTop)
            )
        }

        let recordedFrame = surface.recordedFrame
        let leftInset = recordedContent.x - recordedFrame.x
        let topInset = recordedContent.y - recordedFrame.y
        let rightInset = (recordedFrame.x + recordedFrame.width) - (recordedContent.x + recordedContent.width)
        let bottomInset = (recordedFrame.y + recordedFrame.height) - (recordedContent.y + recordedContent.height)

        return RectValue(
            x: currentFrame.x + leftInset,
            y: currentFrame.y + topInset,
            width: max(1, currentFrame.width - leftInset - rightInset),
            height: max(1, currentFrame.height - topInset - bottomInset)
        )
    }

    func withUndo(_ name: String, _ mutate: () -> Void) {
        let before = MacroEditMutationSnapshot(
            events: recorder.events,
            liveDuration: recorder.liveDuration
        )
        mutate()
        let after = MacroEditMutationSnapshot(
            events: recorder.events,
            liveDuration: recorder.liveDuration
        )
        guard after.differs(from: before) else { return }

        undoManager?.registerUndo(withTarget: recorder) { [weak undoManager] r in
            r.loadEvents(before.events, duration: before.liveDuration)
            undoManager?.registerUndo(withTarget: r) { r2 in
                r2.loadEvents(after.events, duration: after.liveDuration)
            }
        }
        undoManager?.setActionName(name)
        recorder.recalculateStats()
    }

    func startPickingCoordinate(isEndPoint: Bool) {
        guard controller.requireScreenPickingAvailable() else { return }
        guard selection.count == 1, let selectedID = selection.first,
              let selectedRow = rows.first(where: { $0.id == selectedID }) else { return }
        if let macro = editingMacro, macro.followWindowOffset, macro.surfaces.count > 1,
           ((try? MacroPlaybackSurfaceEditing.effectiveSurfaceID(
                in: recorder.events,
                eventIndices: selectedRow.group.eventIndices,
                surfaces: macro.surfaces
           )) ?? nil) == nil {
            state.presentStatus(
                String(localized: "Assign the selected action to one Playback Surface before retargeting its coordinates.", table: "EditorUX"),
                tone: .warning
            )
            return
        }
        // Hide the preview overlay during coordinate picking so it doesn't intercept mouse events
        CoordinatePreviewOverlay.shared.hide()
        
        let editorWin = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.title == String(localized: "Macro Editor", table: "EditorUX") })
        editorWin?.orderOut(nil)
        
        CoordinatePickerOverlay.shared.onPicked = { [weak recorder] pt in
            editorWin?.makeKeyAndOrderFront(nil)
            
            guard selection.count == 1, let selectId = selection.first,
                  let row = rows.first(where: { $0.id == selectId }) else { return }
            
            let grp = row.group
            let currentMacro = editingMacro
            guard let rec = recorder else { return }
            
            var finalPt = pt
            if let macro = currentMacro, macro.followWindowOffset,
               let surfaceID = (try? MacroPlaybackSurfaceEditing.effectiveSurfaceID(
                    in: rec.events,
                    eventIndices: grp.eventIndices,
                    surfaces: macro.surfaces
               )) ?? nil,
               let surface = macro.surfaces[surfaceID] {
                let tracker = WindowTracker()
                let frames = tracker.resolveCurrentFrames(for: [surfaceID: surface])
                if let frame = frames[surfaceID] {
                    let dx = frame.x - surface.recordedFrame.x
                    let dy = frame.y - surface.recordedFrame.y
                    finalPt = CGPoint(x: pt.x - dx, y: pt.y - dy)
                }
            }
            
            if isEndPoint {
                self.withUndo(String(localized: "Pick End Coordinate", table: "Common")) {
                    if let start = grp.startPoint, let end = grp.endPoint {
                        rec.events.conformPath(at: grp.eventIndices, startPoint: start, oldEndPoint: end, newEndPoint: finalPt, surfaces: currentMacro?.surfaces ?? [:])
                    }
                }
            } else {
                self.withUndo(String(localized: "Pick Coordinate", table: "Common")) {
                    let oldStart = grp.startPoint ?? CGPoint.zero
                    let dx = finalPt.x - oldStart.x
                    let dy = finalPt.y - oldStart.y
                    rec.events.translateEvents(at: grp.eventIndices, dx: dx, dy: dy, surfaces: currentMacro?.surfaces ?? [:])
                }
            }
            
            self.updateCachedRows()
            self.loadInspector()
        }
        
        CoordinatePickerOverlay.shared.onCancelled = {
            editorWin?.makeKeyAndOrderFront(nil)
            self.updatePreview() // Restore the preview overlay
        }
        
        guard CoordinatePickerOverlay.shared.start() else {
            editorWin?.makeKeyAndOrderFront(nil)
            self.updatePreview()
            state.presentStatus(
                String(localized: "No display is available for coordinate picking.", table: "EditorUX"),
                tone: .error
            )
            return
        }
    }

    func startPickingAdditionalClickPoint() {
        guard controller.requireScreenPickingAvailable() else { return }
        guard selection.count == 1, let selectedID = selection.first,
              let selectedRow = rows.first(where: { $0.id == selectedID }),
              selectedRow.group.kind == .multiPointClick else { return }
        if let macro = editingMacro, macro.followWindowOffset, macro.surfaces.count > 1,
           ((try? MacroPlaybackSurfaceEditing.effectiveSurfaceID(
                in: recorder.events,
                eventIndices: selectedRow.group.eventIndices,
                surfaces: macro.surfaces
           )) ?? nil) == nil {
            state.presentStatus(
                String(localized: "Assign the selected action to one Playback Surface before retargeting its coordinates.", table: "EditorUX"),
                tone: .warning
            )
            return
        }
        CoordinatePreviewOverlay.shared.hide()

        let editorWin = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.title == String(localized: "Macro Editor", table: "EditorUX") })
        editorWin?.orderOut(nil)

        CoordinatePickerOverlay.shared.onPicked = { [weak recorder] pt in
            editorWin?.makeKeyAndOrderFront(nil)

            guard selection.count == 1, let selectId = selection.first,
                  let row = rows.first(where: { $0.id == selectId }),
                  row.group.kind == .multiPointClick else { return }

            guard let rec = recorder else { return }
            var finalPt = pt
            if let macro = editingMacro, macro.followWindowOffset,
               let surfaceID = (try? MacroPlaybackSurfaceEditing.effectiveSurfaceID(
                    in: rec.events,
                    eventIndices: row.group.eventIndices,
                    surfaces: macro.surfaces
               )) ?? nil,
               let surface = macro.surfaces[surfaceID] {
                let tracker = WindowTracker()
                let frames = tracker.resolveCurrentFrames(for: [surfaceID: surface])
                if let frame = frames[surfaceID] {
                    finalPt = CGPoint(
                        x: pt.x - (frame.x - surface.recordedFrame.x),
                        y: pt.y - (frame.y - surface.recordedFrame.y)
                    )
                }
            }

            let previousLiveDuration = rec.liveDuration
            let previousLastEventTime = rec.events.last?.time
            self.withUndo(String(localized: "Add Click Point", table: "EditorUX")) {
                rec.events.appendMultiPointClick(at: row.group.eventIndices, point: finalPt)
                rec.liveDuration = rec.events.liveDurationPreservingTrailingWait(
                    previousLiveDuration: previousLiveDuration,
                    previousLastEventTime: previousLastEventTime
                )
            }
            self.updateCachedRows()
            self.loadInspector()
        }

        CoordinatePickerOverlay.shared.onCancelled = {
            editorWin?.makeKeyAndOrderFront(nil)
            self.updatePreview()
        }

        guard CoordinatePickerOverlay.shared.start() else {
            editorWin?.makeKeyAndOrderFront(nil)
            self.updatePreview()
            state.presentStatus(
                String(localized: "No display is available for coordinate picking.", table: "EditorUX"),
                tone: .error
            )
            return
        }
    }
    
    @available(macOS 14.0, *)
    func startPickingText() {
        guard controller.requireScreenPickingAvailable() else { return }
        let targetRows = textTargetRowsForCurrentSelection()
        guard !targetRows.isEmpty else { return }
        CoordinatePreviewOverlay.shared.hide()
        
        let targetEventIndices = Array(Set(targetRows.flatMap(\.group.eventIndices))).sorted()
        guard let macro = editingMacro,
              let finalSurfaceId = (try? MacroPlaybackSurfaceEditing.effectiveSurfaceID(
                    in: recorder.events,
                    eventIndices: targetEventIndices,
                    surfaces: macro.surfaces
              )) ?? nil,
              let resolvedSurface = macro.surfaces[finalSurfaceId] else {
            state.presentStatus(
                String(localized: "Choose one Playback Surface for the selected text actions before picking text.", table: "EditorUX"),
                tone: .warning
            )
            return
        }
        
        TextPickerOverlay.shared.onPicked = { [weak recorder] anchor in
            guard let rec = recorder else { return }
            
            self.withUndo(String(localized: "Pick Target Text", table: "EditorUX")) {
                for row in targetRows {
                    rec.events.updateSurfaceId(at: row.group.eventIndices, surfaceId: finalSurfaceId)
                    if row.group.kind.editsSemanticTextTarget {
                        rec.events.updateSemanticAction(
                            at: row.group.eventIndices,
                            textAnchor: anchor,
                            timeout: row.group.textTimeout ?? self.inspTimeout,
                            verifyMustExist: row.group.verifyMustExist ?? true,
                            fallbackPolicy: self.inspFallbackPolicy
                        )
                    } else {
                        rec.events.updateCoordinateStrategy(
                            at: row.group.eventIndices,
                            strategy: .locatorOnly,
                            textAnchor: anchor,
                            fallbackPolicy: self.inspFallbackPolicy,
                            textTimeout: self.inspTimeout
                        )
                    }
                }
            }
            
            self.updateCachedRows()
            self.loadInspector()
        }
        
        TextPickerOverlay.shared.onCancelled = {
            self.updatePreview()
        }
        TextPickerOverlay.shared.onFailed = { message in
            self.state.presentStatus(
                String(
                    format: String(localized: "Could not capture the screen for text picking: %@", table: "EditorUX"),
                    message
                ),
                tone: .error
            )
            self.updatePreview()
        }
        
        TextPickerOverlay.shared.start(targetSurface: resolvedSurface)
    }

    func textTargetRowsForCurrentSelection() -> [ActionRow] {
        let targetIDs = Set(
            ActionGroupProjection.textTargetGroups(
                groups: rows.map(\.group),
                selectedGroupIDs: selection,
                events: recorder.events
            )
            .map(\.id)
        )
        return rows.filter { targetIDs.contains($0.id) }
    }

    func createRepeatUntilDraftFromSelection(maxAttempts: Int, timeoutSeconds: TimeInterval, pollingSeconds: TimeInterval, failurePolicy: String) {
        guard let currentMacro = editingMacro else {
            showRepeatUntilDraftAlert(
                title: String(localized: "No macro selected", table: "EditorUX"),
                message: String(localized: "Select a saved macro before creating a Repeat-Until draft.", table: "EditorUX")
            )
            return
        }

        let bodyMacroID = UUID()
        let bodyMacroName = repeatUntilBodyMacroName(for: currentMacro)
        let plan = MacroEditorRepeatUntilDraftBuilder.plan(
            request: MacroEditorRepeatUntilDraftRequest(
                sourceMacroName: currentMacro.name,
                bodyMacroID: bodyMacroID,
                bodyMacroName: bodyMacroName,
                events: recorder.events,
                groups: rows.map(\.group),
                selectedGroupIDs: selection,
                maxAttempts: maxAttempts,
                timeoutSeconds: timeoutSeconds,
                pollingSeconds: pollingSeconds,
                onFailure: failurePolicy
            )
        )

        guard plan.readiness.canCreate,
              let document = plan.document else {
            showRepeatUntilDraftAlert(
                title: String(localized: "Repeat Until unavailable", table: "Common"),
                message: macroEditorRepeatUntilReadinessHelp(plan.readiness)
            )
            return
        }

        let date = Date()
        let bodyMacro = SavedMacro(
            id: bodyMacroID,
            name: bodyMacroName,
            events: plan.bodyEvents,
            createdAt: date,
            modifiedAt: date,
            surfaces: currentMacro.surfaces,
            followWindowOffset: currentMacro.followWindowOffset,
            icon: currentMacro.icon,
            accent: currentMacro.accent,
            tags: repeatUntilBodyMacroTags(from: currentMacro)
        )
        library.insert(bodyMacro, select: false)

        let catalog = library.macros.map(AutomationWorkflowDraftMacroCatalogEntry.init(macro:))
        repeatUntilDraftPreviewState = AutomationWorkflowDraftPreviewPresenter.previewState(
            document: document,
            sourceName: String(localized: "Macro Editor Repeat Until", table: "EditorUX"),
            macroCatalog: catalog
        )
    }

    func repeatUntilBodyMacroName(for macro: SavedMacro) -> String {
        let selectedBehaviorName = rows
            .filter { selection.contains($0.id) }
            .compactMap { $0.group.behaviorGroupName?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if let selectedBehaviorName {
            return "\(macro.name) - \(selectedBehaviorName)"
        }
        return "\(macro.name) - \(String(localized: "Repeat Body", table: "Common"))"
    }

    func repeatUntilBodyMacroTags(from macro: SavedMacro) -> [String] {
        var tags = macro.tags
        let behaviorTag = String(localized: "Behavior", table: "Common")
        if !tags.contains(behaviorTag) {
            tags.append(behaviorTag)
        }
        return tags.sorted()
    }

    func showRepeatUntilDraftAlert(title: String, message: String) {
        repeatUntilDraftAlertTitle = title
        repeatUntilDraftAlertMessage = message
        isShowingRepeatUntilDraftAlert = true
    }

    func macroEditorRepeatUntilReadinessHelp(_ readiness: MacroEditorRepeatUntilDraftReadiness) -> String {
        switch readiness {
        case .ready:
            return String(localized: "Create a reusable behavior macro and preview the Repeat-Until workflow draft.", table: "Automation")
        case .noSelection:
            return String(localized: "Select a behavior body and one text wait condition.", table: "Automation")
        case .missingBody:
            return String(localized: "Select at least one recorded action as the Repeat-Until body.", table: "Recording")
        case .multipleUntilConditions:
            return String(localized: "Select only one Wait Text, Wait Text Gone, or Verify Text condition.", table: "Automation")
        case .missingUntilCondition:
            return String(localized: "Select one Wait Text, Wait Text Gone, or Verify Text condition as the Until check.", table: "Automation")
        case .missingUntilText:
            return String(localized: "Pick or type target text before creating Repeat Until.", table: "EditorUX")
        }
    }
    
    // MARK: - Context Menu Actions
    
    func toggleDisabledState(for groupIDs: Set<UUID>) {
        let indicesToToggle = rows
            .filter { groupIDs.contains($0.id) }
            .flatMap { $0.group.eventIndices }
        
        guard !indicesToToggle.isEmpty else { return }
        
        let allDisabled = indicesToToggle.allSatisfy { recorder.events[$0].isDisabled == true }
        let newState = !allDisabled
        
        withUndo(newState ? String(localized: "Disable Action", table: "EditorUX") : String(localized: "Enable Action", table: "EditorUX")) {
            for idx in indicesToToggle {
                recorder.events[idx].isDisabled = newState
            }
            _ = updateCachedRows()
            persistEditingEvents()
        }
    }
    
    private func playPartial(events slice: [RecordedEvent]) {
        var mutableSlice = slice
        guard !mutableSlice.isEmpty else { return }
        
        let initialTime = mutableSlice.first?.time ?? 0
        let shift = max(0, initialTime - 0.2)
        for i in mutableSlice.indices {
            mutableSlice[i].time = max(0, mutableSlice[i].time - shift)
        }
        
        controller.playEditorPreview(
            events: mutableSlice,
            sourceMacro: editingMacro
        )
    }

    func playFromHere(anchor row: ActionRow) {
        if let firstIdx = row.group.eventIndices.min(), firstIdx < recorder.events.count {
            playPartial(events: Array(recorder.events[firstIdx...]))
        }
    }
    
    func playThisActionOnly(anchor row: ActionRow) {
        let indices = row.group.eventIndices.sorted()
        let eventsToPlay = indices.compactMap { idx -> RecordedEvent? in
            guard idx < recorder.events.count else { return nil }
            return recorder.events[idx]
        }
        playPartial(events: eventsToPlay)
    }

}

/// Fixed column widths shared by the events header + rows.
enum EventCol {
    static let num: CGFloat = 46
    static let time: CGFloat = 100
    static let pos: CGFloat = 160
    static let key: CGFloat = 80
}
