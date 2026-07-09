import Cocoa
import SwiftUI
import SparkleRecorderCore

/// Visual insertion point used by the action list.
///
/// The list deals in semantic action rows, while the recorder stores raw
/// timestamped events. Keeping this separate from raw event indices lets the UI
/// express the user's intent: place the dragged action before a row, after a row,
/// or at the end.
enum ActionRowInsertion: Equatable {
    case before(UUID)
    case after(UUID)
    case end
    case passthrough

    func isAttached(to rowID: UUID) -> Bool {
        switch self {
        case .before(let id), .after(let id):
            return id == rowID
        case .end, .passthrough:
            return false
        }
    }
}

struct ActionRowDropDelegate: DropDelegate {
    let rowID: UUID
    @Binding var dropInsertion: ActionRowInsertion?
    @Binding var draggedID: UUID?
    @Binding var dragNonce: UInt
    var canDrop: (UUID, ActionRowInsertion) -> Bool
    var onDrop: (UUID, ActionRowInsertion) -> Void

    private let midpoint: CGFloat = 18

    private func insertion(for info: DropInfo) -> ActionRowInsertion {
        info.location.y < midpoint ? .before(rowID) : .after(rowID)
    }

    private func updateInsertion(info: DropInfo) {
        guard let sourceID = draggedID else {
            dropInsertion = nil
            return
        }
        let proposed = insertion(for: info)
        dropInsertion = canDrop(sourceID, proposed) ? proposed : .passthrough
    }

    private func clearDragIfOutsideTargets() {
        let captured = dragNonce
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if dragNonce == captured && dropInsertion == nil {
                draggedID = nil
            }
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        defer {
            dropInsertion = nil
            draggedID = nil
        }
        guard let sourceID = draggedID else { return false }
        let proposed = insertion(for: info)
        guard canDrop(sourceID, proposed) else { return false }
        onDrop(sourceID, proposed)
        return true
    }
    
    func dropEntered(info: DropInfo) {
        dragNonce &+= 1
        updateInsertion(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateInsertion(info: info)
        return DropProposal(operation: .move)
    }
    
    func dropExited(info: DropInfo) {
        if dropInsertion?.isAttached(to: rowID) == true {
            dropInsertion = nil
            clearDragIfOutsideTargets()
        }
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return draggedID != nil
    }
}

struct ActionListEndDropDelegate: DropDelegate {
    @Binding var dropInsertion: ActionRowInsertion?
    @Binding var draggedID: UUID?
    @Binding var dragNonce: UInt
    var canDrop: (UUID, ActionRowInsertion) -> Bool
    var onDrop: (UUID, ActionRowInsertion) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard dropInsertion == .end else { return false }
        
        defer {
            dropInsertion = nil
            draggedID = nil
        }
        guard let sourceID = draggedID, canDrop(sourceID, .end) else { return false }
        onDrop(sourceID, .end)
        return true
    }

    func dropEntered(info: DropInfo) {
        dragNonce &+= 1
        if let current = dropInsertion, current != .end, current != .passthrough {
            return
        }
        guard let sourceID = draggedID else {
            dropInsertion = nil
            return
        }
        dropInsertion = canDrop(sourceID, .end) ? .end : .passthrough
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if let current = dropInsertion, current != .end, current != .passthrough {
            return DropProposal(operation: .move)
        }
        dropEntered(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropInsertion == .end {
            dropInsertion = nil
            clearDragIfOutsideTargets()
        }
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggedID != nil
    }

    private func clearDragIfOutsideTargets() {
        let captured = dragNonce
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if dragNonce == captured && dropInsertion == nil {
                draggedID = nil
            }
        }
    }
}
