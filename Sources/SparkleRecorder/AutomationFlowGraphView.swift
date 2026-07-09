import SwiftUI
import SparkleRecorderCore
import UniformTypeIdentifiers

struct AutomationFlowGraphView: View {
    let workflow: AutomationWorkflowProjection
    let selectedTaskID: UUID?
    let selectedDependencyID: UUID?
    let pendingDependencySourceID: UUID?
    let pendingDependencyTrigger: AutomationDependencyTriggerDraft
    let pendingDependencyTriggerOptions: [AutomationDependencyTriggerDraft]
    let linkPreview: AutomationFlowGraphLinkPreviewState?
    let onSelectTask: (UUID) -> Void
    let onSelectDependency: (UUID) -> Void
    let onDeleteDependency: (UUID) -> Void
    let onStartDependency: (UUID) -> Void
    let onCompleteDependency: (UUID) -> Void
    let onSetPendingDependencyTrigger: (AutomationDependencyTriggerDraft) -> Void
    let onCancelDependency: () -> Void
    let onMacroDropped: (UUID, AutomationGraphPoint) -> Void
    let onAction: (AutomationAction) -> Void
    var now: () -> Date = { Date() }

    @State private var draggedNode: DraggedNode?
    @State private var isGraphDropTargeted = false
    @State private var graphDropLocation: CGPoint?

    private let dragThreshold = 3.0
    private let graphInset = 32.0

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    AutomationFlowGraphEdgeCanvas(edges: dynamicEdges)
                        .frame(
                            width: CGFloat(dynamicGraphSize.width),
                            height: CGFloat(dynamicGraphSize.height)
                        )

                    if let linkPreview,
                       let start = linkPreviewStart(for: linkPreview) {
                        AutomationFlowGraphLinkPreview(
                            start: start,
                            end: linkPreview.end
                        )
                            .frame(
                                width: CGFloat(dynamicGraphSize.width),
                                height: CGFloat(dynamicGraphSize.height)
                            )
                    }

                    AutomationFlowGraphEdgeListView(
                        edges: dynamicEdges,
                        selectedDependencyID: selectedDependencyID,
                        onSelectDependency: onSelectDependency,
                        onDeleteDependency: onDeleteDependency
                    )

                    ForEach(workflow.nodes) { node in
                        nodeView(for: node)
                    }
                }
                .frame(
                    width: CGFloat(dynamicGraphSize.width),
                    height: CGFloat(dynamicGraphSize.height),
                    alignment: .topLeading
                )
                .contentShape(Rectangle())
                .overlay(graphDropOverlay)
                .onDrop(
                    of: [UTType.text],
                    delegate: AutomationFlowGraphDropDelegate(
                        isTargeted: $isGraphDropTargeted,
                        dropLocation: $graphDropLocation,
                        onDrop: handleGraphDrop(providers:location:)
                    )
                )
                .coordinateSpace(name: "AutomationFlowGraphCanvas")
            }
            .scrollIndicators(.hidden)

            // Header Overlay
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(workflow.name)
                            .font(.headline)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Label(String(format: NSLocalizedString("%d tasks", comment: ""), workflow.nodes.count), systemImage: "circle.grid.cross")
                            Label(String(format: NSLocalizedString("%d links", comment: ""), workflow.edges.count), systemImage: "arrow.triangle.branch")
                            Label(workflow.status.label, systemImage: workflow.status.systemImage)
                                .foregroundStyle(workflow.status.tint)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if pendingDependencySourceID != nil {
                        AutomationFlowGraphLinkingToolbar(
                            trigger: pendingDependencyTrigger,
                            triggerOptions: pendingDependencyTriggerOptions,
                            onSetTrigger: onSetPendingDependencyTrigger,
                            onCancel: onCancelDependency
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Material.regular)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.1), radius: 2)

                Spacer()
            }
            .padding(16)
        }
        .onChange(of: workflow.nodes) {
            if let dragged = draggedNode, dragged.isCommitted {
                if let updatedNode = workflow.nodes.first(where: { $0.taskID == dragged.taskID }),
                   abs(updatedNode.position.x - dragged.displayPosition.x) < 1.0,
                   abs(updatedNode.position.y - dragged.displayPosition.y) < 1.0 {
                    draggedNode = nil
                }
            }
        }
    }

    private func nodeView(for node: AutomationTaskNodeProjection) -> some View {
        AutomationFlowGraphNodeView(
            node: node,
            size: workflow.nodeSize,
            isSelected: selectedTaskID == node.taskID,
            isConnectionSource: pendingDependencySourceID == node.taskID,
            canCompleteConnection: canCompleteConnection(to: node.taskID),
            connectionTriggerTitle: pendingDependencyTrigger.title,
            onSelect: {
                onSelectTask(node.taskID)
            },
            onRun: {
                startTask(node.taskID)
            },
            onCancelRun: { runID in
                cancelRun(runID)
            },
            onConnect: {
                connect(to: node.taskID)
            },
            isDragging: isDragging(node.taskID)
        )
        .offset(
            x: CGFloat(displayPosition(for: node).x),
            y: CGFloat(displayPosition(for: node).y)
        )
        .simultaneousGesture(dragGesture(for: node))
    }

    private func linkPreviewStart(for preview: AutomationFlowGraphLinkPreviewState) -> AutomationGraphPoint? {
        guard let node = workflow.nodes.first(where: { $0.taskID == preview.sourceTaskID }) else {
            return nil
        }

        return AutomationGraphPoint(
            x: displayPosition(for: node).x + workflow.nodeSize.width,
            y: displayPosition(for: node).y + (workflow.nodeSize.height / 2)
        )
    }

    private var dynamicEdges: [AutomationDependencyEdgeProjection] {
        guard let draggedNode,
              draggedNode.hasExceededThreshold(dragThreshold) else {
            return workflow.edges
        }

        let offset = draggedNode.movementOffset
        return workflow.edges.map { edge in
            var copy = edge
            if edge.fromTaskID == draggedNode.taskID {
                copy.start = copy.start.offsetBy(offset)
            }
            if edge.toTaskID == draggedNode.taskID {
                copy.end = copy.end.offsetBy(offset)
            }
            return copy
        }
    }

    private var dynamicGraphSize: AutomationGraphSize {
        guard let draggedNode,
              draggedNode.hasExceededThreshold(dragThreshold) else {
            return workflow.graphSize
        }

        let movedMaxX = draggedNode.displayPosition.x + workflow.nodeSize.width + graphInset
        let movedMaxY = draggedNode.displayPosition.y + workflow.nodeSize.height + graphInset
        return AutomationGraphSize(
            width: max(workflow.graphSize.width, movedMaxX),
            height: max(workflow.graphSize.height, movedMaxY)
        )
    }

    private var graphDropOverlay: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isGraphDropTargeted ? Brand.libraryGreen.opacity(0.72) : Color.clear,
                    style: StrokeStyle(lineWidth: 1.2, dash: [7, 5])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isGraphDropTargeted ? Brand.libraryGreen.opacity(0.045) : Color.clear)
                )

            if workflow.nodes.isEmpty {
                AutomationFlowGraphEmptyCanvasView(isActive: isGraphDropTargeted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if isGraphDropTargeted, let graphDropLocation {
                let position = graphDropPosition(for: graphDropLocation)
                AutomationFlowGraphDropPreview(size: workflow.nodeSize)
                    .offset(x: CGFloat(position.x), y: CGFloat(position.y))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func dragGesture(for node: AutomationTaskNodeProjection) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("AutomationFlowGraphCanvas"))
            .onChanged { value in
                let translation = AutomationGraphPoint(
                    x: Double(value.translation.width),
                    y: Double(value.translation.height)
                )
                if draggedNode?.taskID != node.taskID {
                    draggedNode = DraggedNode(
                        taskID: node.taskID,
                        startPosition: node.position,
                        translation: translation
                    )
                } else {
                    draggedNode?.translation = translation
                }
            }
            .onEnded { value in
                let translation = AutomationGraphPoint(
                    x: Double(value.translation.width),
                    y: Double(value.translation.height)
                )
                let distance = hypot(translation.x, translation.y)

                guard distance >= dragThreshold else {
                    draggedNode = nil
                    onSelectTask(node.taskID)
                    return
                }

                draggedNode?.translation = translation
                draggedNode?.isCommitted = true

                let finalPosition = node.position.offsetBy(translation).clampedToPositive()
                onSelectTask(node.taskID)
                onAction(.moveTask(
                    workflowID: workflow.id,
                    taskID: node.taskID,
                    position: finalPosition,
                    at: now()
                ))
            }
    }

    private func displayPosition(for node: AutomationTaskNodeProjection) -> AutomationGraphPoint {
        guard let draggedNode,
              draggedNode.taskID == node.taskID,
              draggedNode.hasExceededThreshold(dragThreshold) else {
            return node.position
        }

        return draggedNode.displayPosition
    }

    private func isDragging(_ taskID: UUID) -> Bool {
        guard let draggedNode,
              draggedNode.taskID == taskID else {
            return false
        }
        return draggedNode.hasExceededThreshold(dragThreshold)
    }

    private func handleGraphDrop(providers: [NSItemProvider], location: CGPoint) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }

        let dropPosition = graphDropPosition(for: location)
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? String,
                  let droppedItem = DroppedItem(payload: payload) else {
                return
            }

            Task { @MainActor in
                switch droppedItem {
                case .macro(let macroID):
                    onMacroDropped(macroID, dropPosition)
                case .task(let taskID):
                    onSelectTask(taskID)
                    onAction(.moveTask(
                        workflowID: workflow.id,
                        taskID: taskID,
                        position: dropPosition,
                        at: now()
                    ))
                }
            }
        }
        return true
    }

    private func graphDropPosition(for location: CGPoint) -> AutomationGraphPoint {
        AutomationGraphPoint(
            x: max(0, Double(location.x) - workflow.nodeSize.width / 2),
            y: max(0, Double(location.y) - workflow.nodeSize.height / 2)
        )
    }

    private func canCompleteConnection(to taskID: UUID) -> Bool {
        pendingDependencySourceID != nil && pendingDependencySourceID != taskID
    }

    private func connect(to taskID: UUID) {
        if canCompleteConnection(to: taskID) {
            onCompleteDependency(taskID)
        } else {
            onStartDependency(taskID)
        }
    }

    private func startTask(_ taskID: UUID) {
        let intent = AutomationViewIntent.startTask(
            workflowID: workflow.id,
            taskID: taskID
        )
        onAction(intent.reducerAction(at: now()))
    }

    private func cancelRun(_ runID: UUID) {
        onAction(.cancelRun(runID: runID, at: now()))
    }

    private struct DraggedNode: Equatable {
        var taskID: UUID
        var startPosition: AutomationGraphPoint
        var translation: AutomationGraphPoint
        var isCommitted: Bool = false

        var displayPosition: AutomationGraphPoint {
            startPosition.offsetBy(translation).clampedToPositive()
        }

        var movementOffset: AutomationGraphPoint {
            AutomationGraphPoint(
                x: displayPosition.x - startPosition.x,
                y: displayPosition.y - startPosition.y
            )
        }

        func hasExceededThreshold(_ threshold: Double) -> Bool {
            isCommitted || hypot(translation.x, translation.y) >= threshold
        }
    }

    private enum DroppedItem {
        case macro(UUID)
        case task(UUID)

        init?(payload: String) {
            if let macroID = AutomationMacroDragPayload.macroID(from: payload) {
                self = .macro(macroID)
            } else if let taskID = AutomationTaskDragPayload.taskID(from: payload) {
                self = .task(taskID)
            } else {
                return nil
            }
        }
    }
}

private struct AutomationFlowGraphDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    @Binding var dropLocation: CGPoint?
    let onDrop: ([NSItemProvider], CGPoint) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: [UTType.text]).isEmpty
    }

    func dropEntered(info: DropInfo) {
        updateDropState(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropState(info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        dropLocation = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.text])
        let location = info.location
        isTargeted = false
        dropLocation = nil
        return onDrop(providers, location)
    }

    private func updateDropState(_ info: DropInfo) {
        isTargeted = true
        dropLocation = info.location
    }
}

private struct AutomationFlowGraphDropPreview: View {
    let size: AutomationGraphSize

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Brand.libraryGreen.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Brand.libraryGreen.opacity(0.68),
                        style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])
                    )
            )
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Brand.libraryGreen)
                    .padding(7)
                    .background(.thinMaterial, in: Circle())
            }
            .frame(width: CGFloat(size.width), height: CGFloat(size.height))
    }
}

private struct AutomationFlowGraphEmptyCanvasView: View {
    let isActive: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.grid.cross")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(isActive ? Brand.libraryGreen : Color.secondary.opacity(0.6))
                .accessibilityHidden(true)

            Text(NSLocalizedString("No task nodes", comment: ""))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? Brand.libraryGreen : Color.secondary)

            Text(NSLocalizedString("Workflow structure appears here.", comment: ""))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
    }
}

private extension AutomationGraphPoint {
    func offsetBy(_ offset: AutomationGraphPoint) -> AutomationGraphPoint {
        AutomationGraphPoint(
            x: x + offset.x,
            y: y + offset.y
        )
    }

    func clampedToPositive() -> AutomationGraphPoint {
        AutomationGraphPoint(
            x: max(0, x),
            y: max(0, y)
        )
    }
}
