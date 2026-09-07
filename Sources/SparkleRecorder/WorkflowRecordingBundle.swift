import Foundation
import SparkleRecorderCore

/// Portable recording-bundle values consumed by workflow CLI tooling.
///
/// File-system lookup stays in the app-side `RecordingCLIBundleLoader` Adapter;
/// the tooling Module only depends on these values and the loader Seam supplied
/// by its caller.
package typealias WorkflowRecordingAdditionalOptionHandler = (
    _ token: String,
    _ index: Int,
    _ arguments: [String]
) throws -> Int?

package typealias WorkflowRecordingBundleLoader = (
    _ arguments: [String],
    _ additionalOptionHandler: WorkflowRecordingAdditionalOptionHandler?
) throws -> RecordingCLIBundle

package struct RecordingCLIBundle: Sendable {
    package var requestedRecordingID: String
    package var fixture: String?
    package var sourceOption: String?
    package var bundleDirectory: URL?
    package var bundle: SemanticRecordingBundle

    package init(
        requestedRecordingID: String,
        fixture: String?,
        sourceOption: String?,
        bundleDirectory: URL?,
        bundle: SemanticRecordingBundle
    ) {
        self.requestedRecordingID = requestedRecordingID
        self.fixture = fixture
        self.sourceOption = sourceOption
        self.bundleDirectory = bundleDirectory
        self.bundle = bundle
    }
}

package struct RecordingCLIBundleLoad: Sendable {
    package var requestedRecordingID: String
    package var fixture: String?
    package var sourceOption: String?
    package var bundleDirectory: URL?
    package var loadResult: SemanticRecordingBundleLoadResult

    package init(
        requestedRecordingID: String,
        fixture: String?,
        sourceOption: String?,
        bundleDirectory: URL?,
        loadResult: SemanticRecordingBundleLoadResult
    ) {
        self.requestedRecordingID = requestedRecordingID
        self.fixture = fixture
        self.sourceOption = sourceOption
        self.bundleDirectory = bundleDirectory
        self.loadResult = loadResult
    }

    package var bundle: SemanticRecordingBundle {
        loadResult.bundle
    }
}
