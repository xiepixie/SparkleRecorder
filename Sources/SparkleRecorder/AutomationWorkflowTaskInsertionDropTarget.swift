import SwiftUI
import UniformTypeIdentifiers

struct AutomationWorkflowTaskInsertionDropTarget: View {
    let index: Int
    @Binding var activeInsertionIndex: Int?
    let onDropMacro: (UUID, Int) -> Void
    let onDropTask: (UUID, Int) -> Void

    @State private var isTargeted = false

    private var isActive: Bool {
        activeInsertionIndex == index
    }

    var body: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(isActive ? Brand.libraryGreen : Color.primary.opacity(0.12))
                .frame(height: isActive ? 2 : 1)

            if isActive {
                Text("Insert here", tableName: "Common")
                    .font(.caption)
                    .foregroundStyle(Brand.libraryGreen)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: isActive ? 18 : 8)
        .contentShape(Rectangle())
        .onDrop(
            of: [UTType.text],
            isTargeted: $isTargeted,
            perform: handleMacroDrop(providers:)
        )
        .onChange(of: isTargeted) {
            updateActiveInsertionIndex()
        }
        .accessibilityLabel(String(localized: "Drop task or macro here", table: "Common"))
        .accessibilityValue(String(format: String(localized: "Insert at position %d", table: "Common"), index + 1))
    }

    private func updateActiveInsertionIndex() {
        if isTargeted {
            activeInsertionIndex = index
        } else if activeInsertionIndex == index {
            activeInsertionIndex = nil
        }
    }

    private func handleMacroDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? String,
                  let item = Self.droppedItem(from: payload) else {
                return
            }

            Task { @MainActor in
                activeInsertionIndex = nil
                switch item {
                case .macro(let macroID):
                    onDropMacro(macroID, index)
                case .task(let taskID):
                    onDropTask(taskID, index)
                }
            }
        }
        return true
    }

    nonisolated private static func droppedItem(from payload: String) -> DroppedItem? {
        if let macroID = AutomationMacroDragPayload.macroID(from: payload) {
            return .macro(macroID)
        }
        if let taskID = AutomationTaskDragPayload.taskID(from: payload) {
            return .task(taskID)
        }
        return nil
    }

    private enum DroppedItem {
        case macro(UUID)
        case task(UUID)
    }
}
