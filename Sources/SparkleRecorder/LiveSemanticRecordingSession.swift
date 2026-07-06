import Foundation
import SparkleRecorderCore

enum LiveSemanticRecordingSessionError: Error, Equatable {
    case alreadyStarted
    case notStarted
    case alreadyFinished
}

enum LiveSemanticRecordingStartResult: Equatable {
    case started(preflight: SemanticRecordingPreflightResult, bundleDirectory: URL)
    case blocked(preflight: SemanticRecordingPreflightResult)

    var preflight: SemanticRecordingPreflightResult {
        switch self {
        case .started(let preflight, _), .blocked(let preflight):
            return preflight
        }
    }
}

struct LiveSemanticRecordingFinishResult: Equatable {
    var bundle: SemanticRecordingBundle
    var bundleDirectory: URL
    var redactionResult: RecordingBundleRedactionApplicationResult?
}

struct LiveSemanticRecordingSessionDependencies: @unchecked Sendable {
    var store: RecordingBundleStore
    var preflightClient: SemanticRecordingPreflightClient
    var suppressionProducer: SemanticRecordingSuppressionProducer
    var makeCaptureClient: @Sendable (URL) -> SemanticRecordingCaptureClient

    init(
        store: RecordingBundleStore = RecordingBundleStore(),
        preflightClient: SemanticRecordingPreflightClient = .live,
        suppressionProducer: SemanticRecordingSuppressionProducer = .liveUserDefaults,
        makeCaptureClient: @escaping @Sendable (URL) -> SemanticRecordingCaptureClient = { directory in
            LiveSemanticCaptureClient.live(bundleDirectory: directory)
        }
    ) {
        self.store = store
        self.preflightClient = preflightClient
        self.suppressionProducer = suppressionProducer
        self.makeCaptureClient = makeCaptureClient
    }
}

actor LiveSemanticRecordingSession {
    private let configuration: SemanticRecordingCaptureConfiguration
    private let dependencies: LiveSemanticRecordingSessionDependencies

    private var lifecycle: SemanticRecordingLifecycle?
    private var bundleDirectory: URL?
    private var didFinish = false

    init(
        configuration: SemanticRecordingCaptureConfiguration = SemanticRecordingCaptureConfiguration(),
        dependencies: LiveSemanticRecordingSessionDependencies = LiveSemanticRecordingSessionDependencies()
    ) {
        self.configuration = configuration
        self.dependencies = dependencies
    }

    func start(recordingTime: TimeInterval = 0) async throws -> LiveSemanticRecordingStartResult {
        guard !didFinish else {
            throw LiveSemanticRecordingSessionError.alreadyFinished
        }
        guard lifecycle == nil else {
            throw LiveSemanticRecordingSessionError.alreadyStarted
        }

        let lifecycleConfiguration = SemanticRecordingLifecycleConfiguration(
            captureConfiguration: configuration
        )
        let preflight = await dependencies.preflightClient.evaluate(
            policy: lifecycleConfiguration.preflightPolicy
        )
        guard preflight.isReadyToStart else {
            return .blocked(preflight: preflight)
        }

        let directory = try await dependencies.store.createBundleDirectory(
            recordingID: configuration.recordingID
        )
        let captureClient = dependencies.makeCaptureClient(directory)
        let sessionFactory = SemanticRecordingCaptureSessionFactory { configuration in
            SemanticRecordingCaptureSession(
                configuration: configuration,
                client: captureClient
            )
        }
        let lifecycle = SemanticRecordingLifecycle(
            configuration: lifecycleConfiguration,
            preflightClient: .fixed(preflight.snapshot),
            sessionFactory: sessionFactory
        )

        self.lifecycle = lifecycle
        bundleDirectory = directory
        do {
            switch try await lifecycle.start(recordingTime: recordingTime) {
            case .started(let startedPreflight):
                return .started(preflight: startedPreflight, bundleDirectory: directory)
            case .blocked(let blockedPreflight):
                await cleanupBundleDirectory(recordingTime: recordingTime)
                return .blocked(preflight: blockedPreflight)
            }
        } catch {
            await cleanupBundleDirectory(recordingTime: recordingTime)
            didFinish = true
            throw error
        }
    }

    func record(_ event: RecordedEvent, index: Int) async throws {
        try await requireLifecycle().record(event, index: index)
    }

    func addSuppression(_ suppression: RecordingSuppressionRecord) async throws {
        try await requireLifecycle().addSuppression(suppression)
    }

    @discardableResult
    func addSuppressions(
        for context: SemanticRecordingSuppressionContext
    ) async throws -> [RecordingSuppressionRecord] {
        let suppressions = dependencies.suppressionProducer.records(for: context)
        for suppression in suppressions {
            try await addSuppression(suppression)
        }
        return suppressions
    }

    func finish(recordingTime: TimeInterval) async throws -> LiveSemanticRecordingFinishResult {
        let activeLifecycle = try requireLifecycle()
        guard let directory = bundleDirectory else {
            throw LiveSemanticRecordingSessionError.notStarted
        }

        do {
            let bundle = try await activeLifecycle.finish(recordingTime: recordingTime)
            try await dependencies.store.write(bundle, to: directory)
            let redactionPlan = SemanticRecordingRedactionPlanner.plan(for: bundle)
            let redactionResult: RecordingBundleRedactionApplicationResult?
            if redactionPlan.isEmpty {
                redactionResult = nil
            } else {
                redactionResult = try await dependencies.store.applyRedactionPlan(
                    redactionPlan,
                    dryRun: false
                )
            }
            lifecycle = nil
            bundleDirectory = nil
            didFinish = true
            return LiveSemanticRecordingFinishResult(
                bundle: bundle,
                bundleDirectory: directory,
                redactionResult: redactionResult
            )
        } catch {
            await cleanupBundleDirectory(recordingTime: recordingTime)
            didFinish = true
            throw error
        }
    }

    func cancel(recordingTime: TimeInterval) async {
        guard !didFinish else {
            return
        }

        await cleanupBundleDirectory(recordingTime: recordingTime)
        didFinish = true
    }

    private func cleanupBundleDirectory(recordingTime: TimeInterval) async {
        if let activeLifecycle = lifecycle {
            await activeLifecycle.cancel(recordingTime: recordingTime)
        }

        _ = try? await dependencies.store.removeBundleDirectory(
            recordingID: configuration.recordingID
        )
        lifecycle = nil
        bundleDirectory = nil
    }

    private func requireLifecycle() throws -> SemanticRecordingLifecycle {
        guard !didFinish else {
            throw LiveSemanticRecordingSessionError.alreadyFinished
        }
        guard let lifecycle else {
            throw LiveSemanticRecordingSessionError.notStarted
        }
        return lifecycle
    }
}
