import Foundation
import SparkleRecorderCore

private final class PlaybackEvidenceResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: AutomationRunEvidencePersistence?

    var value: AutomationRunEvidencePersistence? {
        lock.withLock { storage }
    }

    func store(_ value: AutomationRunEvidencePersistence) {
        lock.withLock { storage = value }
    }
}

struct PlaybackEvidenceClient: Sendable {
    var recordFailure: @Sendable (PlaybackFailureEvidence) async -> AutomationRunEvidencePersistence?
    var recordFailureSynchronously: @Sendable (PlaybackFailureEvidence) -> AutomationRunEvidencePersistence?

    init(
        recordFailure: @escaping @Sendable (PlaybackFailureEvidence) async -> AutomationRunEvidencePersistence?,
        recordFailureSynchronously: @escaping @Sendable (PlaybackFailureEvidence) -> AutomationRunEvidencePersistence?
    ) {
        self.recordFailure = recordFailure
        self.recordFailureSynchronously = recordFailureSynchronously
    }

    static let none = PlaybackEvidenceClient(
        recordFailure: { _ in nil },
        recordFailureSynchronously: { _ in nil }
    )

    static let live = PlaybackEvidenceClient(
        recordFailure: { evidence in
            await EvidenceClient.shared.recordFailure(evidence)
        },
        recordFailureSynchronously: { evidence in
            let semaphore = DispatchSemaphore(value: 0)
            let result = PlaybackEvidenceResultBox()
            Task {
                let persistence = await EvidenceClient.shared.recordFailure(evidence)
                result.store(persistence)
                semaphore.signal()
            }
            semaphore.wait()
            return result.value
        }
    )
}
