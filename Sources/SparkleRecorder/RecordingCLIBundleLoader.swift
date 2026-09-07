import Foundation
import SparkleRecorderCore
import SparkleRecorderTooling

enum RecordingCLIBundleLoader {
    typealias AdditionalOptionHandler = (String, Int, [String]) throws -> Int?

    static func load(
        _ arguments: [String],
        additionalOptionHandler: AdditionalOptionHandler? = nil
    ) throws -> RecordingCLIBundle {
        let request = try parseSource(
            arguments,
            additionalOptionHandler: additionalOptionHandler
        )

        if let fixture = request.fixture {
            try validateFixture(fixture)
            try validateFixtureRecordingID(request.requestedRecordingID)
            return RecordingCLIBundle(
                requestedRecordingID: request.requestedRecordingID,
                fixture: fixture,
                sourceOption: nil,
                bundleDirectory: nil,
                bundle: SemanticRecordingFixture.checkoutBundle()
            )
        }

        let requestedUUID = try parseRecordingID(request.requestedRecordingID)
        if let recordingsRoot = request.recordingsRoot {
            let store = RecordingBundleStore(rootDirectory: recordingsRoot)
            let bundle = try waitForWorkflowCLIAsync {
                try await store.loadBundle(recordingID: requestedUUID)
            }
            return RecordingCLIBundle(
                requestedRecordingID: request.requestedRecordingID,
                fixture: nil,
                sourceOption: sourceOption("--recordings-root", url: recordingsRoot),
                bundleDirectory: recordingsRoot.appendingPathComponent(
                    SemanticRecordingBundleDirectoryIdentity.directoryName(for: requestedUUID),
                    isDirectory: true
                ),
                bundle: bundle
            )
        }

        guard let bundlePath = request.bundlePath else {
            let defaultRoot = RecordingBundleStore.defaultRootDirectory
            let store = RecordingBundleStore(rootDirectory: defaultRoot)
            let bundle = try waitForWorkflowCLIAsync {
                try await store.loadBundle(recordingID: requestedUUID)
            }
            return RecordingCLIBundle(
                requestedRecordingID: request.requestedRecordingID,
                fixture: nil,
                sourceOption: nil,
                bundleDirectory: defaultRoot.appendingPathComponent(
                    SemanticRecordingBundleDirectoryIdentity.directoryName(for: requestedUUID),
                    isDirectory: true
                ),
                bundle: bundle
            )
        }

        let store = RecordingBundleStore(rootDirectory: bundlePath.deletingLastPathComponent())
        let bundle = try waitForWorkflowCLIAsync {
            try await store.loadBundle(from: bundlePath)
        }
        try validateRequestedRecordingID(
            requestedUUID,
            bundleID: bundle.id,
            bundlePath: bundlePath
        )
        return RecordingCLIBundle(
            requestedRecordingID: request.requestedRecordingID,
            fixture: nil,
            sourceOption: sourceOption("--bundle-path", url: bundlePath),
            bundleDirectory: bundlePath,
            bundle: bundle
        )
    }

    static func loadTolerant(
        _ arguments: [String],
        additionalOptionHandler: AdditionalOptionHandler? = nil
    ) throws -> RecordingCLIBundleLoad {
        let request = try parseSource(
            arguments,
            additionalOptionHandler: additionalOptionHandler
        )

        if let fixture = request.fixture {
            try validateFixture(fixture)
            try validateFixtureRecordingID(request.requestedRecordingID)
            return RecordingCLIBundleLoad(
                requestedRecordingID: request.requestedRecordingID,
                fixture: fixture,
                sourceOption: nil,
                bundleDirectory: nil,
                loadResult: SemanticRecordingBundleLoadResult(
                    manifest: SemanticRecordingFixture.checkoutBundle()
                )
            )
        }

        let requestedUUID = try parseRecordingID(request.requestedRecordingID)
        if let recordingsRoot = request.recordingsRoot {
            let store = RecordingBundleStore(rootDirectory: recordingsRoot)
            let loadResult = try waitForWorkflowCLIAsync {
                try await store.loadBundleTolerant(recordingID: requestedUUID)
            }
            return RecordingCLIBundleLoad(
                requestedRecordingID: request.requestedRecordingID,
                fixture: nil,
                sourceOption: sourceOption("--recordings-root", url: recordingsRoot),
                bundleDirectory: recordingsRoot.appendingPathComponent(
                    SemanticRecordingBundleDirectoryIdentity.directoryName(for: requestedUUID),
                    isDirectory: true
                ),
                loadResult: loadResult
            )
        }

        guard let bundlePath = request.bundlePath else {
            let defaultRoot = RecordingBundleStore.defaultRootDirectory
            let store = RecordingBundleStore(rootDirectory: defaultRoot)
            let loadResult = try waitForWorkflowCLIAsync {
                try await store.loadBundleTolerant(recordingID: requestedUUID)
            }
            return RecordingCLIBundleLoad(
                requestedRecordingID: request.requestedRecordingID,
                fixture: nil,
                sourceOption: nil,
                bundleDirectory: defaultRoot.appendingPathComponent(
                    SemanticRecordingBundleDirectoryIdentity.directoryName(for: requestedUUID),
                    isDirectory: true
                ),
                loadResult: loadResult
            )
        }

        let store = RecordingBundleStore(rootDirectory: bundlePath.deletingLastPathComponent())
        let loadResult = try waitForWorkflowCLIAsync {
            try await store.loadBundleTolerant(from: bundlePath)
        }
        try validateRequestedRecordingID(
            requestedUUID,
            bundleID: loadResult.bundle.id,
            bundlePath: bundlePath
        )
        return RecordingCLIBundleLoad(
            requestedRecordingID: request.requestedRecordingID,
            fixture: nil,
            sourceOption: sourceOption("--bundle-path", url: bundlePath),
            bundleDirectory: bundlePath,
            loadResult: loadResult
        )
    }

    static func validateFixture(_ fixture: String) throws {
        guard fixture == "checkout" else {
            throw WorkflowCLIError(
                "unsupportedFixture",
                "Unsupported recording fixture '\(fixture)'. Use '--fixture checkout'.",
                path: fixture
            )
        }
    }

    static func sourceOption(_ option: String, url: URL) -> String {
        " \(option) \(shellQuote(url.path))"
    }

    private struct SourceRequest {
        var requestedRecordingID: String
        var fixture: String?
        var recordingsRoot: URL?
        var bundlePath: URL?
    }

    private static func parseSource(
        _ arguments: [String],
        additionalOptionHandler: AdditionalOptionHandler?
    ) throws -> SourceRequest {
        guard let requestedRecordingID = arguments.first,
              !requestedRecordingID.hasPrefix("--") else {
            throw WorkflowCLIError(
                "missingArgument",
                "Expected a recording id, such as 'checkout-demo'."
            )
        }

        var fixture: String?
        var recordingsRoot: URL?
        var bundlePath: URL?
        var index = 1
        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--json":
                break
            case "--fixture":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError(
                        "missingArgument",
                        "--fixture requires a fixture name.",
                        path: token
                    )
                }
                fixture = arguments[index + 1]
                index += 1
            case "--recordings-root":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError(
                        "missingArgument",
                        "--recordings-root requires a path.",
                        path: token
                    )
                }
                recordingsRoot = URL(
                    fileURLWithPath: arguments[index + 1],
                    isDirectory: true
                ).standardizedFileURL
                index += 1
            case "--bundle-path", "--bundle-dir":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError(
                        "missingArgument",
                        "\(token) requires a path.",
                        path: token
                    )
                }
                bundlePath = URL(
                    fileURLWithPath: arguments[index + 1],
                    isDirectory: true
                ).standardizedFileURL
                index += 1
            default:
                if let consumed = try additionalOptionHandler?(token, index, arguments) {
                    index += consumed
                } else if token.hasPrefix("--") {
                    throw WorkflowCLIError(
                        "unsupportedOption",
                        "Unsupported option '\(token)'.",
                        path: token
                    )
                } else {
                    throw WorkflowCLIError(
                        "unexpectedArgument",
                        "Unexpected argument '\(token)'.",
                        path: token
                    )
                }
            }
            index += 1
        }

        let sourceCount = [fixture != nil, recordingsRoot != nil, bundlePath != nil]
            .filter { $0 }
            .count
        guard sourceCount <= 1 else {
            throw WorkflowCLIError(
                "conflictingRecordingSource",
                "Use only one recording source: --fixture, --recordings-root, or --bundle-path.",
                path: "--recordings-root"
            )
        }

        return SourceRequest(
            requestedRecordingID: requestedRecordingID,
            fixture: fixture,
            recordingsRoot: recordingsRoot,
            bundlePath: bundlePath
        )
    }

    private static func validateFixtureRecordingID(_ requestedRecordingID: String) throws {
        let acceptedRecordingIDs = Set([
            "checkout-demo",
            "recording-checkout-demo",
            SemanticRecordingFixture.recordingID.uuidString.lowercased()
        ])
        guard acceptedRecordingIDs.contains(requestedRecordingID.lowercased()) else {
            throw WorkflowCLIError(
                "unknownRecording",
                "Fixture 'checkout' exposes recording id 'checkout-demo'.",
                path: requestedRecordingID
            )
        }
    }

    private static func parseRecordingID(_ value: String) throws -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            throw WorkflowCLIError(
                "invalidUUID",
                "recording-id must be a UUID.",
                path: "recording-id"
            )
        }
        return uuid
    }

    private static func validateRequestedRecordingID(
        _ requestedID: UUID,
        bundleID: UUID,
        bundlePath: URL
    ) throws {
        guard bundleID == requestedID else {
            throw WorkflowCLIError(
                "recordingMismatch",
                "Bundle at '\(bundlePath.path)' contains recording '\(bundleID.uuidString)', not '\(requestedID.uuidString)'.",
                path: "--bundle-path"
            )
        }
    }

    private static func shellQuote(_ value: String) -> String {
        let safeScalars = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./:-"
        )
        guard !value.isEmpty else {
            return "''"
        }
        if value.unicodeScalars.allSatisfy({ safeScalars.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
