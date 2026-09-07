import SwiftUI

struct AutomationExternalSignalSourceView: View {
    let signalName: String

    @State private var sourceState = AutomationExternalSignalSourceState()

    var body: some View {
        Toggle(
            String(localized: "Signal active", table: "Common"),
            isOn: Binding(
                get: { sourceState.isActive },
                set: { setActiveFromUser($0) }
            )
        )
        .toggleStyle(.switch)
        .disabled(trimmedSignalName.isEmpty)
        .task(id: trimmedSignalName) {
            await loadSignal()
        }
    }

    private var trimmedSignalName: String {
        signalName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func loadSignal() async {
        guard let request = sourceState.beginLoad(signalName: signalName) else {
            return
        }
        let active = await AutomationSignalStore.shared.isActive(request.signalName)
        guard !Task.isCancelled else { return }
        sourceState.applyLoaded(active, request: request)
    }

    @MainActor
    private func setActiveFromUser(_ active: Bool) {
        guard let request = sourceState.userSetActive(active, signalName: signalName) else {
            return
        }
        Task {
            await AutomationSignalStore.shared.setActive(
                request.isActive,
                signalName: request.signalName
            )
        }
    }
}
