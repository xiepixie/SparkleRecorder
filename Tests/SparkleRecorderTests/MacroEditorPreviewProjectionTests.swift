import CoreGraphics
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Macro Editor Preview Projection Tests")
struct MacroEditorPreviewProjectionTests {
    @Test("Coordinate actions share one simulated Playback Surface")
    func coordinateActionsShareSimulatedSurface() throws {
        let surface = PlaybackSurface(
            appName: "Example",
            windowTitle: "Document",
            recordedFrame: RectValue(x: 900, y: 500, width: 1200, height: 900),
            recordedContentFrame: RectValue(x: 900, y: 528, width: 1200, height: 872)
        )

        var click = RecordedEvent.make(
            .leftMouseDown,
            time: 0,
            x: 1200,
            y: 790,
            mouseButton: 0,
            clickCount: 1
        )
        bind(&click, surfaceID: "main", normalizedX: 0.25, normalizedY: 0.30)

        var dragDown = RecordedEvent.make(
            .leftMouseDown,
            time: 1,
            x: 1320,
            y: 876,
            mouseButton: 0,
            clickCount: 1
        )
        bind(&dragDown, surfaceID: "main", normalizedX: 0.35, normalizedY: 0.40)

        var dragged = RecordedEvent.make(
            .leftMouseDragged,
            time: 1.1,
            x: 1680,
            y: 1050,
            mouseButton: 0,
            clickCount: 1
        )
        bind(&dragged, surfaceID: "main", normalizedX: 0.65, normalizedY: 0.60)

        var dragUp = RecordedEvent.make(
            .leftMouseUp,
            time: 1.2,
            x: 1800,
            y: 1137,
            mouseButton: 0,
            clickCount: 1
        )
        bind(&dragUp, surfaceID: "main", normalizedX: 0.75, normalizedY: 0.70)

        let events = [click, dragDown, dragged, dragUp]
        let clickGroup = ActionGroup(
            kind: .click,
            eventIndices: [0],
            startTime: 0,
            endTime: 0,
            startPoint: CGPoint(x: click.x, y: click.y),
            summary: "Click"
        )
        let dragGroup = ActionGroup(
            kind: .drag,
            eventIndices: [1, 2, 3],
            startTime: 1,
            endTime: 1.2,
            startPoint: CGPoint(x: dragDown.x, y: dragDown.y),
            endPoint: CGPoint(x: dragUp.x, y: dragUp.y),
            path: [
                CGPoint(x: dragDown.x, y: dragDown.y),
                CGPoint(x: dragged.x, y: dragged.y),
                CGPoint(x: dragUp.x, y: dragUp.y)
            ],
            summary: "Drag"
        )
        let macro = SavedMacro(
            name: "Preview",
            events: events,
            surfaces: ["main": surface],
            followWindowOffset: true
        )
        let liveContext = PlaybackContext(
            surfaces: macro.surfaces,
            coordinateMode: .boundWindowOffset
        )

        let result = MacroEditorPreviewProjector.project(
            items: [
                MacroEditorPreviewItem(id: clickGroup.id, group: clickGroup, order: 1),
                MacroEditorPreviewItem(id: dragGroup.id, group: dragGroup, order: 2)
            ],
            events: events,
            liveContext: liveContext,
            previewCanvas: RectValue(x: 0, y: 0, width: 1400, height: 900),
            activeScreenUnion: CGRect(x: 0, y: 0, width: 1400, height: 900),
            hideMouseMoves: false
        )

        let clickPreview = try #require(result.actions.first { $0.id == clickGroup.id })
        let dragPreview = try #require(result.actions.first { $0.id == dragGroup.id })
        let clickBackdrop = try #require(clickPreview.surfaceBackdrop)
        let dragBackdrop = try #require(dragPreview.surfaceBackdrop)
        let clickPoint = try #require(clickPreview.selectedPoint)

        #expect(clickBackdrop.frame == dragBackdrop.frame)
        #expect(clickBackdrop.frame.contains(clickPoint))
        #expect(dragPreview.dragPath.count == 3)
        #expect(dragPreview.dragPath.allSatisfy(clickBackdrop.frame.contains))
        #expect(result.coordinateEditContexts[clickGroup.id] != nil)
        #expect(result.coordinateEditContexts[dragGroup.id] != nil)
    }

    @Test("Preview only shows the selection as detailed actions")
    func previewOnlyShowsSelection() {
        let rows = previewRows()
        let selectedID = rows[0].id
        let plan = MacroEditorPreviewDisplayPlan.make(
            rows: rows,
            selection: [selectedID],
            showsSelectedPreview: true,
            showsAllPaths: false
        )

        #expect(plan.items.map(\.id) == [selectedID])
        #expect(plan.detailActionIDs == [selectedID])
        #expect(plan.focusedActionID == selectedID)
    }

    @Test("Paths only shows every action as a passive overview")
    func pathsOnlyShowsGlobalOverview() {
        let rows = previewRows()
        let plan = MacroEditorPreviewDisplayPlan.make(
            rows: rows,
            selection: [rows[0].id],
            showsSelectedPreview: false,
            showsAllPaths: true
        )

        #expect(plan.items.map(\.id) == rows.map(\.id))
        #expect(plan.detailActionIDs.isEmpty)
        #expect(plan.focusedActionID == nil)
    }

    @Test("Preview and Paths combine global overview with selected detail")
    func previewAndPathsCompose() {
        let rows = previewRows()
        let selectedID = rows[1].id
        let plan = MacroEditorPreviewDisplayPlan.make(
            rows: rows,
            selection: [selectedID],
            showsSelectedPreview: true,
            showsAllPaths: true
        )

        #expect(plan.items.map(\.id) == rows.map(\.id))
        #expect(plan.detailActionIDs == [selectedID])
        #expect(plan.focusedActionID == selectedID)
    }

    @Test("Preview without a selection and Paths off produces no overlay actions")
    func previewWithoutSelectionIsEmpty() {
        let plan = MacroEditorPreviewDisplayPlan.make(
            rows: previewRows(),
            selection: [],
            showsSelectedPreview: true,
            showsAllPaths: false
        )

        #expect(plan.items.isEmpty)
        #expect(plan.detailActionIDs.isEmpty)
        #expect(plan.focusedActionID == nil)
    }

    @Test("Live Playback Surface geometry does not create a simulated backdrop")
    func liveSurfaceDoesNotCreateBackdrop() throws {
        let surface = PlaybackSurface(
            appName: "Example",
            recordedFrame: RectValue(x: 100, y: 80, width: 1000, height: 700),
            recordedContentFrame: RectValue(x: 100, y: 108, width: 1000, height: 672)
        )
        var click = RecordedEvent.make(
            .leftMouseDown,
            time: 0,
            x: 350,
            y: 310,
            mouseButton: 0,
            clickCount: 1
        )
        bind(&click, surfaceID: "main", normalizedX: 0.25, normalizedY: 0.30)
        let group = ActionGroup(
            kind: .click,
            eventIndices: [0],
            startTime: 0,
            endTime: 0,
            startPoint: CGPoint(x: click.x, y: click.y),
            summary: "Click"
        )
        let macro = SavedMacro(
            name: "Preview",
            events: [click],
            surfaces: ["main": surface],
            followWindowOffset: true
        )
        let liveWindow = RectValue(x: 300, y: 150, width: 1000, height: 700)
        let liveContent = RectValue(x: 300, y: 178, width: 1000, height: 672)
        let liveContext = PlaybackContext(
            surfaces: macro.surfaces,
            currentSurfaceFrames: ["main": liveWindow],
            currentContentFrames: ["main": liveContent],
            coordinateMode: .boundWindowOffset
        )

        let result = MacroEditorPreviewProjector.project(
            items: [MacroEditorPreviewItem(id: group.id, group: group, order: 1)],
            events: [click],
            liveContext: liveContext,
            previewCanvas: RectValue(x: 0, y: 0, width: 1400, height: 900),
            activeScreenUnion: CGRect(x: 0, y: 0, width: 1400, height: 900),
            hideMouseMoves: false
        )
        let preview = try #require(result.actions.first)
        let point = try #require(preview.selectedPoint)

        #expect(preview.surfaceBackdrop == nil)
        #expect(liveContent.cgRect.contains(point))
        #expect(result.coordinateEditContexts[group.id] == nil)
    }

    private func previewRows() -> [ActionRow] {
        [
            ActionRow(group: ActionGroup(
                kind: .click,
                eventIndices: [0],
                startTime: 0,
                endTime: 0,
                summary: "Click"
            )),
            ActionRow(group: ActionGroup(
                kind: .drag,
                eventIndices: [1, 2],
                startTime: 1,
                endTime: 1.2,
                summary: "Drag"
            ))
        ]
    }

    private func bind(
        _ event: inout RecordedEvent,
        surfaceID: String,
        normalizedX: CGFloat,
        normalizedY: CGFloat
    ) {
        event.surfaceId = surfaceID
        event.coordinateBinding = .targetWindow
        event.coordinateStrategy = .normalizedPreferred
        event.contentNormalizedX = normalizedX
        event.contentNormalizedY = normalizedY
    }
}
