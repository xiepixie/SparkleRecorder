import SwiftUI

struct AutomationExternalSignalSourceView: View {
    let signalName: String

    @State private var isActive = false

    var body: some View {
        Toggle(NSLocalizedString("Signal active", comment: ""), isOn: $isActive)
            .toggleStyle(.switch)
            .disabled(trimmedSignalName.isEmpty)
            .onChange(of: isActive) {
                updateSignal()
            }
            .task(id: trimmedSignalName) {
                await loadSignal()
            }
    }

    private var trimmedSignalName: String {
        signalName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadSignal() async {
        guard !trimmedSignalName.isEmpty else {
            isActive = false
            return
        }
        isActive = await AutomationSignalStore.shared.isActive(trimmedSignalName)
    }

    private func updateSignal() {
        Task {
            await AutomationSignalStore.shared.setActive(isActive, signalName: trimmedSignalName)
        }
    }
}
