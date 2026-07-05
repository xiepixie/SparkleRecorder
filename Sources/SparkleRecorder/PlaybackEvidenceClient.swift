import Foundation
import SparkleRecorderCore

struct PlaybackEvidenceClient: Sendable {
    var recordFailure: @Sendable (PlaybackFailureEvidence) async -> Void
    var recordFailureSynchronously: @Sendable (PlaybackFailureEvidence) -> Void

    init(
        recordFailure: @escaping @Sendable (PlaybackFailureEvidence) async -> Void,
        recordFailureSynchronously: @escaping @Sendable (PlaybackFailureEvidence) -> Void
    ) {
        self.recordFailure = recordFailure
        self.recordFailureSynchronously = recordFailureSynchronously
    }

    static let none = PlaybackEvidenceClient(
        recordFailure: { _ in },
        recordFailureSynchronously: { _ in }
    )

    static let live = PlaybackEvidenceClient(
        recordFailure: { evidence in
            await EvidenceClient.shared.recordFailure(evidence)
        },
        recordFailureSynchronously: { evidence in
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await EvidenceClient.shared.recordFailure(evidence)
                semaphore.signal()
            }
            semaphore.wait()
        }
    )
}
