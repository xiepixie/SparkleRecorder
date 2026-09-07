import Foundation
import SparkleRecorderCore

enum SemanticRecordingReviewRepeatUntilBodyPresentation {
    static func message(
        for resolution: SemanticRecordingReviewRepeatUntilBodyResolution
    ) -> String {
        switch resolution.status {
        case .resolved:
            if let macroName = resolution.bodyTasks.first?.name,
               !macroName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return String(
                    format: String(localized: "Repeat-Until body will replay %@.", table: "Common"),
                    macroName
                )
            }
            return String(localized: "Repeat-Until body is ready.", table: "Common")
        case .noLinkedMacro:
            return String(
                localized: "Link this semantic recording to a macro before creating a Repeat-Until body.",
                table: "Common"
            )
        case .ambiguousLinkedMacros:
            return String(
                localized: "Multiple macros are linked to this recording. Choose one as the Repeat-Until body.",
                table: "Common"
            )
        }
    }
}
