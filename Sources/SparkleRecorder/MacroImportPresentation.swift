import Foundation
import SparkleRecorderCore

enum MacroImportPresentation {
    static func errorMessage(_ error: Error) -> String {
        guard let error = error as? MacroImportError else {
            return error.localizedDescription
        }

        switch error {
        case .empty:
            return String(localized: "The macro file is empty.", table: "Common")
        case .notRecFormat:
            return String(
                localized: "This is not a supported legacy Windows .rec macro.",
                table: "Common"
            )
        case .notTextFormat:
            return String(
                localized: "This is not a supported SparkleRecorder text macro.",
                table: "Common"
            )
        case .unreadable:
            return String(localized: "The macro file format is not recognized.", table: "Common")
        }
    }

    static func warning(
        skippedEntryCount: Int,
        legacyVersionWarning: Bool
    ) -> String? {
        guard skippedEntryCount > 0 else { return nil }

        if legacyVersionWarning {
            return String(
                format: String(
                    localized: "Some records could not be imported (%d skipped). The file may use an unsupported legacy recorder format.",
                    table: "Common"
                ),
                skippedEntryCount
            )
        }

        return String(
            format: String(
                localized: "Some entries could not be imported (%d skipped).",
                table: "Common"
            ),
            skippedEntryCount
        )
    }
}
