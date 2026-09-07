import Foundation
import SparkleRecorderCore

enum SemanticRecorderBridgeStatus: Equatable, Sendable {
    case idle
    case starting
    case active(bundleDirectory: URL)
    case blocked(preflight: SemanticRecordingPreflightResult)
    case finishing(bundleDirectory: URL)
    case finished(bundleID: UUID, bundleDirectory: URL, eventCount: Int)
    case cancelled
    case suppressed(message: String)
    case failed(message: String)
}

actor SemanticRecorderBridge {
    private let makeSession: @Sendable () -> LiveSemanticRecordingSession

    private var session: LiveSemanticRecordingSession?
    private var activeBundleDirectory: URL?
    private var pendingEvents: [(event: RecordedEvent, sessionTime: Double?)] = []
    private var pendingEvidenceSamples: [RecordingEvidenceSample] = []
    private var pendingPlayableEvidenceLinks: [RecordingPlayableEvidenceLink] = []
    private var pendingOmittedEvidenceSampleCount = 0
    private var pendingSuppressionContexts: [SemanticRecordingSuppressionContext] = []
    private var nextEventIndex = 0
    private var status: SemanticRecorderBridgeStatus = .idle

    init(
        configuration: SemanticRecordingCaptureConfiguration = SemanticRecordingCaptureConfiguration()
    ) {
        self.makeSession = {
            LiveSemanticRecordingSession(configuration: configuration)
        }
    }

    init(
        makeSession: @escaping @Sendable () -> LiveSemanticRecordingSession
    ) {
        self.makeSession = makeSession
    }

    func currentStatus() -> SemanticRecorderBridgeStatus {
        status
    }

    func start(recordingTime: TimeInterval = 0, sessionOriginHostTime: Double? = nil) async -> SemanticRecorderBridgeStatus {
        switch status {
        case .idle, .cancelled, .failed:
            break
        default:
            return status
        }

        status = .starting
        let session = makeSession()
        self.session = session

        do {
            switch try await session.start(recordingTime: recordingTime, sessionOriginHostTime: sessionOriginHostTime) {
            case .started(_, let bundleDirectory):
                guard self.session === session,
                      case .starting = status else {
                    await session.cancel(recordingTime: recordingTime)
                    return status
                }
                activeBundleDirectory = bundleDirectory
                status = .active(bundleDirectory: bundleDirectory)
                _ = await recordPendingEvents()
                _ = await recordPendingEvidence()
                return await recordPendingSuppressions()

            case .blocked(let preflight):
                guard self.session === session,
                      case .starting = status else {
                    await session.cancel(recordingTime: recordingTime)
                    return status
                }
                self.session = nil
                activeBundleDirectory = nil
                clearPendingRecordingData()
                status = .blocked(preflight: preflight)
                return status
            }
        } catch {
            guard self.session === session,
                  case .starting = status else {
                return status
            }
            return await fail(
                session: session,
                recordingTime: recordingTime,
                error: error
            )
        }
    }

    func record(_ events: [RecordedEvent], sessionTimeOffset: Double? = nil) async -> SemanticRecorderBridgeStatus {
        guard !events.isEmpty else {
            return status
        }

        switch status {
        case .idle, .starting:
            pendingEvents.append(contentsOf: events.map { event in (event, sessionTimeOffset.map { $0 + event.time }) })
            return status

        case .active:
            return await recordActiveEvents(events.map { event in (event, sessionTimeOffset.map { $0 + event.time }) })

        default:
            return status
        }
    }

    func recordEvidence(
        samples: [RecordingEvidenceSample],
        playableLinks: [RecordingPlayableEvidenceLink],
        omittedSampleCount: Int = 0,
        sessionTimeOffset: Double? = nil
    ) async -> SemanticRecorderBridgeStatus {
        guard !samples.isEmpty || !playableLinks.isEmpty || omittedSampleCount > 0 else {
            return status
        }
        let projectedSamples = samples.map { $0.projectingSessionTime(offset: sessionTimeOffset) }

        switch status {
        case .idle, .starting:
            pendingEvidenceSamples.append(contentsOf: projectedSamples)
            pendingPlayableEvidenceLinks.append(contentsOf: playableLinks)
            pendingOmittedEvidenceSampleCount += max(0, omittedSampleCount)
            return status

        case .active:
            return await recordActiveEvidence(
                samples: projectedSamples,
                playableLinks: playableLinks,
                omittedSampleCount: omittedSampleCount
            )

        default:
            return status
        }
    }

    func addSuppressions(
        for context: SemanticRecordingSuppressionContext
    ) async -> SemanticRecorderBridgeStatus {
        switch status {
        case .idle, .starting:
            pendingSuppressionContexts.append(context)
            return status

        case .active:
            return await addActiveSuppressions([context])

        default:
            return status
        }
    }

    func finish(
        recordingTime: TimeInterval,
        finalPlayableEvents: [RecordedEvent]
    ) async -> SemanticRecorderBridgeStatus {
        guard let session else {
            clearPendingRecordingData()
            return status
        }

        if case .active(let bundleDirectory) = status {
            status = .finishing(bundleDirectory: bundleDirectory)
        }

        do {
            let result = try await session.finish(
                recordingTime: recordingTime,
                finalPlayableEvents: finalPlayableEvents
            )
            self.session = nil
            activeBundleDirectory = nil
            clearPendingRecordingData()
            status = .finished(
                bundleID: result.bundle.id,
                bundleDirectory: result.bundleDirectory,
                eventCount: result.bundle.timelineEvents.count
            )
            return status
        } catch {
            return await fail(
                session: session,
                recordingTime: recordingTime,
                error: error
            )
        }
    }

    func cancel(recordingTime: TimeInterval) async -> SemanticRecorderBridgeStatus {
        clearPendingRecordingData()
        guard let session else {
            activeBundleDirectory = nil
            status = .cancelled
            return status
        }

        await session.cancel(recordingTime: recordingTime)
        self.session = nil
        activeBundleDirectory = nil
        status = .cancelled
        return status
    }

    func suppress(
        recordingTime: TimeInterval,
        message: String
    ) async -> SemanticRecorderBridgeStatus {
        clearPendingRecordingData()
        if let session {
            await session.cancel(recordingTime: recordingTime)
        }
        self.session = nil
        activeBundleDirectory = nil
        status = .suppressed(message: message)
        return status
    }

    private func recordPendingEvents() async -> SemanticRecorderBridgeStatus {
        let events = pendingEvents
        pendingEvents.removeAll()
        return await recordActiveEvents(events)
    }

    private func recordPendingEvidence() async -> SemanticRecorderBridgeStatus {
        let samples = pendingEvidenceSamples
        let links = pendingPlayableEvidenceLinks
        let omitted = pendingOmittedEvidenceSampleCount
        pendingEvidenceSamples.removeAll()
        pendingPlayableEvidenceLinks.removeAll()
        pendingOmittedEvidenceSampleCount = 0
        return await recordActiveEvidence(
            samples: samples,
            playableLinks: links,
            omittedSampleCount: omitted
        )
    }

    private func recordPendingSuppressions() async -> SemanticRecorderBridgeStatus {
        let contexts = pendingSuppressionContexts
        pendingSuppressionContexts.removeAll()
        return await addActiveSuppressions(contexts)
    }

    private func recordActiveEvents(
        _ events: [(event: RecordedEvent, sessionTime: Double?)]
    ) async -> SemanticRecorderBridgeStatus {
        guard let session else {
            pendingEvents.removeAll()
            status = .failed(message: "Semantic recording session is missing.")
            return status
        }

        do {
            for event in events {
                try await session.record(event.event, index: nextEventIndex, sessionTime: event.sessionTime)
                nextEventIndex += 1
            }
            return status
        } catch {
            return await fail(
                session: session,
                recordingTime: events.last?.sessionTime ?? events.last?.event.time ?? 0,
                error: error
            )
        }
    }

    private func recordActiveEvidence(
        samples: [RecordingEvidenceSample],
        playableLinks: [RecordingPlayableEvidenceLink],
        omittedSampleCount: Int
    ) async -> SemanticRecorderBridgeStatus {
        guard let session else {
            clearPendingRecordingData()
            status = .failed(message: "Semantic recording session is missing.")
            return status
        }

        do {
            try await session.recordEvidence(
                samples: samples,
                playableLinks: playableLinks,
                omittedSampleCount: omittedSampleCount
            )
            return status
        } catch {
            let recordingTime = samples.last?.sessionTime
                ?? samples.last?.sourcePlaybackTime
                ?? 0
            return await fail(
                session: session,
                recordingTime: recordingTime,
                error: error
            )
        }
    }

    private func addActiveSuppressions(
        _ contexts: [SemanticRecordingSuppressionContext]
    ) async -> SemanticRecorderBridgeStatus {
        guard !contexts.isEmpty else {
            return status
        }
        guard let session else {
            pendingSuppressionContexts.removeAll()
            status = .failed(message: "Semantic recording session is missing.")
            return status
        }

        do {
            for context in contexts {
                _ = try await session.addSuppressions(for: context)
            }
            return status
        } catch {
            return await fail(
                session: session,
                recordingTime: contexts.last?.recordingTime ?? 0,
                error: error
            )
        }
    }

    private func fail(
        session failedSession: LiveSemanticRecordingSession?,
        recordingTime: TimeInterval,
        error: Error
    ) async -> SemanticRecorderBridgeStatus {
        await failedSession?.cancel(recordingTime: recordingTime)
        if failedSession === session {
            session = nil
        }
        activeBundleDirectory = nil
        clearPendingRecordingData()
        status = .failed(message: String(describing: error))
        return status
    }

    private func clearPendingRecordingData() {
        pendingEvents.removeAll()
        pendingEvidenceSamples.removeAll()
        pendingPlayableEvidenceLinks.removeAll()
        pendingOmittedEvidenceSampleCount = 0
        pendingSuppressionContexts.removeAll()
    }
}
