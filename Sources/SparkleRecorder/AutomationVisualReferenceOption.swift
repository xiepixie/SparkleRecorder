import Foundation

struct AutomationVisualReferenceOption: Identifiable, Equatable {
    var key: String
    var label: String?
    var detail: String?

    var id: String { key }

    var title: String {
        guard let label, !label.isEmpty else {
            return key
        }
        return label
    }

    var subtitle: String? {
        if let detail, !detail.isEmpty {
            return detail
        }
        if let label, !label.isEmpty, label != key {
            return key
        }
        return nil
    }
}
