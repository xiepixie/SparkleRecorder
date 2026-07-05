import Foundation
import SparkleRecorderCore

actor AutomationSignalStore {
    static let shared = AutomationSignalStore()

    private var activeSignals: Set<String> = []

    func isActive(_ signalName: String) -> Bool {
        activeSignals.contains(normalized(signalName))
    }

    func setActive(_ isActive: Bool, signalName: String) {
        let key = normalized(signalName)
        guard !key.isEmpty else {
            return
        }

        if isActive {
            activeSignals.insert(key)
        } else {
            activeSignals.remove(key)
        }
    }

    private func normalized(_ signalName: String) -> String {
        signalName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension AutomationExternalSignalClient {
    static func appSignals(_ store: AutomationSignalStore = .shared) -> AutomationExternalSignalClient {
        AutomationExternalSignalClient { signalName in
            await store.isActive(signalName)
        }
    }
}
