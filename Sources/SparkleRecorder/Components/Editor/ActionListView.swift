import Cocoa
import SwiftUI
import SparkleRecorderCore

struct ActionListView: View {
    @EnvironmentObject var library: MacroLibrary
    @EnvironmentObject var recorder: Recorder
    @Environment(\.undoManager) private var undoManager
    let rows: [ActionRow]
    @Binding var selection: Set<UUID>
    let onRefreshRows: () -> [ActionRow]
    @State private var lastAnchor: UUID?
    @State private var dropInsertion: ActionRowInsertion? = nil
    @State private var draggedID: UUID? = nil

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
	                    if rows.isEmpty {
	                        VStack(spacing: 8) {
	                            Image(systemName: "sparkles.rectangle.stack")
	                                .font(.system(size: 22, weight: .semibold))
	                                .foregroundStyle(.secondary)
	                            Text(NSLocalizedString("No actions yet", comment: ""))
	                                .font(.system(size: 12, weight: .semibold))
	                            Text(NSLocalizedString("Record a macro or insert an action from the sidebar.", comment: ""))
	                                .font(.system(size: 10.5))
	                                .foregroundStyle(.secondary)
	                        }
	                        .frame(maxWidth: .infinity, minHeight: 170)
	                    }
	                    
	                    LazyVStack(spacing: 0) {
	                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            ActionRowView(
                                row: row,
                                order: index + 1,
                                selected: selection.contains(row.id),
                                isMoving: isMoving(row),
                                onTap: { mods in handleTap(row.id, mods: mods) },
                                onDragStarted: { beginDrag(row.id) },
                                draggedID: $draggedID
                            )
                            .overlay(alignment: .top) {
                                insertionIndicator(isActive: dropInsertion == .before(row.id))
                            }
                            .overlay(alignment: .bottom) {
                                insertionIndicator(isActive: dropInsertion == .after(row.id))
                            }
                            .onDrop(of: [.text], delegate: ActionRowDropDelegate(
                                rowID: row.id,
                                dropInsertion: $dropInsertion,
                                draggedID: $draggedID,
                                canDrop: canDrop,
                                onDrop: moveRows
                            ))
                            .contextMenu {
                                rowContextMenu(for: row)
                            }
	                        }
                        
                        Color.clear
                            .frame(height: 32)
                            .contentShape(Rectangle())
                            .onDrop(of: [.text], delegate: ActionListEndDropDelegate(
                                dropInsertion: $dropInsertion,
                                draggedID: $draggedID,
                                canDrop: canDrop,
                                onDrop: moveRows
                            ))
                            .overlay(alignment: .top) {
                                insertionIndicator(isActive: dropInsertion == .end)
                            }
	                    }
	                }
	            }
	            .sectionSurface(cornerRadius: 12)
	            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func insertionIndicator(isActive: Bool) -> some View {
        if isActive {
            HStack(spacing: 0) {
                Circle()
                    .fill(Brand.accent(library.currentMacro?.accent))
                    .frame(width: 6, height: 6)
                Rectangle()
                    .fill(Brand.accent(library.currentMacro?.accent))
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .shadow(color: Brand.accent(library.currentMacro?.accent).opacity(0.32), radius: 3, y: 1)
            .allowsHitTesting(false)
        }
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

    func withUndo(_ name: String, _ mutate: () -> Void) {
        let snapshot = recorder.events
        let snapshotDur = recorder.liveDuration
        undoManager?.registerUndo(withTarget: recorder) { [weak undoManager] r in
            let redoSnapshot = r.events
            let redoDur = r.liveDuration
            r.loadEvents(snapshot, duration: snapshotDur)
            undoManager?.registerUndo(withTarget: r) { r2 in
                r2.loadEvents(redoSnapshot, duration: redoDur)
            }
        }
        undoManager?.setActionName(name)
        mutate()
        recorder.recalculateStats()
    }

    private var reorderableRows: [ActionRow] {
        rows.filter { $0.group.kind.isReorderableAction }
    }

    func beginDrag(_ id: UUID) {
        guard reorderableRows.contains(where: { $0.id == id }) else { return }
        if !selection.contains(id) {
            selection = [id]
            lastAnchor = id
        }
        draggedID = id
    }

    func isMoving(_ row: ActionRow) -> Bool {
        guard let sourceID = draggedID else { return false }
        return movingGroupIDs(for: sourceID).contains(row.id)
    }

    func movingGroupIDs(for sourceID: UUID) -> Set<UUID> {
        let proposed = selection.contains(sourceID) ? selection : [sourceID]
        let reorderableIDs = Set(reorderableRows.map(\.id))
        return proposed.intersection(reorderableIDs)
    }

    func canDrop(sourceID: UUID, insertion: ActionRowInsertion) -> Bool {
        let movingGroupIDs = movingGroupIDs(for: sourceID)
        guard !movingGroupIDs.isEmpty else { return false }

        switch insertion {
        case .before(let targetID), .after(let targetID):
            guard !movingGroupIDs.contains(targetID),
                  reorderableRows.contains(where: { $0.id == targetID }) else {
                return false
            }
        case .end:
            break
        }

        guard let proposedOrder = visibleOrderAfterMove(movingGroupIDs: movingGroupIDs, to: insertion) else {
            return false
        }
        return proposedOrder != reorderableRows.map(\.id)
    }

    func visibleOrderAfterMove(movingGroupIDs: Set<UUID>, to insertion: ActionRowInsertion) -> [UUID]? {
        var order = reorderableRows.map(\.id)
        let movingInOrder = order.filter { movingGroupIDs.contains($0) }
        guard !movingInOrder.isEmpty else { return nil }

        order.removeAll { movingGroupIDs.contains($0) }

        let insertIndex: Int
        switch insertion {
        case .before(let targetID):
            guard let idx = order.firstIndex(of: targetID) else { return nil }
            insertIndex = idx
        case .after(let targetID):
            guard let idx = order.firstIndex(of: targetID) else { return nil }
            insertIndex = idx + 1
        case .end:
            insertIndex = order.count
        }

        order.insert(contentsOf: movingInOrder, at: insertIndex)
        return order
    }

    func targetEventIndex(for insertion: ActionRowInsertion, movingGroupIDs: Set<UUID>) -> Int? {
        switch insertion {
        case .before(let targetID):
            return rows.first { $0.id == targetID && $0.group.kind.isReorderableAction }?.group.eventIndices.first
        case .after(let targetID):
            guard let targetRowIndex = rows.firstIndex(where: { $0.id == targetID }) else { return nil }
            // `reorderGroup` only accepts "before event" targets. Dropping after
            // a row is represented as "before the next non-moving action"; if
            // there is no next action, nil means append to the end.
            return rows.dropFirst(targetRowIndex + 1)
                .first { $0.group.kind.isReorderableAction && !movingGroupIDs.contains($0.id) }?
                .group.eventIndices.first
        case .end:
            return nil
        }
    }

    func moveRows(sourceID: UUID, insertion: ActionRowInsertion) {
        let movingGroupIDs = movingGroupIDs(for: sourceID)
        guard canDrop(sourceID: sourceID, insertion: insertion) else { return }

        // Move the underlying raw events as one semantic action block. Wait
        // rows are derived from timing gaps and intentionally stay out of the
        // moving set; the transformer preserves the gaps between actions.
        let movingRows = rows.filter { movingGroupIDs.contains($0.id) && $0.group.kind.isReorderableAction }
        let sourceEventIndices = movingRows.flatMap { $0.group.eventIndices }
        guard !sourceEventIndices.isEmpty else { return }

        let targetEventIndex = targetEventIndex(for: insertion, movingGroupIDs: movingGroupIDs)
        let count = sourceEventIndices.count
        let adjTargetIndex: Int
        if let targetIdx = targetEventIndex {
            adjTargetIndex = targetIdx - sourceEventIndices.filter { $0 < targetIdx }.count
        } else {
            adjTargetIndex = recorder.events.count - count
        }
        let movedRange = adjTargetIndex ..< (adjTargetIndex + count)

        withUndo(NSLocalizedString("Move Action", comment: "")) {
            recorder.events.reorderGroup(sourceEventIndices: sourceEventIndices, beforeEventIndex: targetEventIndex)
        }

        selectMovedRows(in: movedRange)
    }

    func selectMovedRows(in eventIndexRange: Range<Int>) {
        let movedRows = onRefreshRows().filter { row in
            row.group.eventIndices.contains { eventIndexRange.contains($0) }
        }
        if !movedRows.isEmpty {
            selection = Set(movedRows.map(\.id))
            lastAnchor = movedRows.first?.id
        }
    }

	    func handleTap(_ id: UUID, mods: NSEvent.ModifierFlags) {
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
    
    @ViewBuilder
    func rowContextMenu(for row: ActionRow) -> some View {
        let snapshot = contextSnapshot(anchor: row)

        Button {
            selection = [row.id]
            lastAnchor = row.id
        } label: {
            Label(NSLocalizedString("Select Action", comment: ""), systemImage: "checkmark.circle")
        }
        
        Divider()
        
        Button {
            duplicateRows(anchor: row)
        } label: {
            Label(NSLocalizedString("Duplicate Action", comment: ""), systemImage: "plus.square.on.square")
        }
        .disabled(snapshot.eventIndices.isEmpty)
        
        Button(role: .destructive) {
            deleteRows(anchor: row)
        } label: {
            Label(NSLocalizedString("Delete Actions", comment: ""), systemImage: "trash")
        }
        .disabled(snapshot.eventIndices.isEmpty)
        
        Divider()
        
        Button {
            bindRows(anchor: row)
        } label: {
            Label(NSLocalizedString("Bind Behavior", comment: ""), systemImage: "square.stack.3d.down.right")
        }
        .disabled(!snapshot.canBindBehavior)
        
        Button {
            unbindRows(anchor: row)
        } label: {
            Label(NSLocalizedString("Unbind Behavior", comment: ""), systemImage: "square.stack.3d.down.forward")
        }
        .disabled(!snapshot.containsBehavior)
    }

    func contextSnapshot(anchor row: ActionRow) -> ActionGroupSelectionSnapshot {
        let selectedGroupIDs = selection.contains(row.id) ? selection : [row.id]
        return ActionGroupProjection.selectionSnapshot(
            groups: rows.map(\.group),
            selectedGroupIDs: selectedGroupIDs,
            events: recorder.events
        )
    }
    
    func contextRows(anchor row: ActionRow) -> [ActionRow] {
        let selectedIDs = Set(contextSnapshot(anchor: row).groupIDs)
        return rows.filter { selectedIDs.contains($0.id) }
    }
    
    func contextEventIndices(anchor row: ActionRow) -> [Int] {
        contextSnapshot(anchor: row).eventIndices
    }

    func contextContainsBehavior(anchor row: ActionRow) -> Bool {
        contextSnapshot(anchor: row).containsBehavior
    }
    
    func duplicateRows(anchor row: ActionRow) {
        let indices = contextSnapshot(anchor: row).eventIndices
        guard !indices.isEmpty else { return }
        let afterIdx = indices.last! + 1
        let copiesRange = afterIdx..<(afterIdx + indices.count)
        
        withUndo(NSLocalizedString("Duplicate Action", comment: "")) {
            recorder.events.duplicateEvents(at: indices)
        }
        
        DispatchQueue.main.async {
            let copied = self.rows.filter { item in
                item.group.eventIndices.contains(where: { copiesRange.contains($0) })
            }
            if !copied.isEmpty {
                self.selection = Set(copied.map(\.id))
            }
        }
    }
    
    func deleteRows(anchor row: ActionRow) {
        let snapshot = contextSnapshot(anchor: row)
        let indices = snapshot.eventIndices
        guard !indices.isEmpty else { return }
        selection.subtract(snapshot.groupIDs)
        withUndo(NSLocalizedString("Delete Actions", comment: "")) {
            recorder.events.deleteEvents(at: IndexSet(indices))
        }
    }
    
    func bindRows(anchor row: ActionRow) {
        let indices = contextSnapshot(anchor: row).eventIndices
        guard indices.count >= 2 else { return }
        let existing = recorder.events.compactMap(\.behaviorGroupID).reduce(into: Set<BehaviorGroupID>()) { partial, item in
            partial.insert(item)
        }
        let id = BehaviorGroupID()
        let name = String(format: NSLocalizedString("Behavior %d", comment: ""), existing.count + 1)
        
        withUndo(NSLocalizedString("Bind Behavior", comment: "")) {
            recorder.events.bindBehavior(at: indices, id: id, name: name)
        }
    }
    
    func unbindRows(anchor row: ActionRow) {
        let snapshot = contextSnapshot(anchor: row)
        let indices = snapshot.eventIndices
        guard !indices.isEmpty, snapshot.containsBehavior else { return }
        withUndo(NSLocalizedString("Unbind Behavior", comment: "")) {
            recorder.events.unbindBehavior(at: indices)
        }
    }
}
