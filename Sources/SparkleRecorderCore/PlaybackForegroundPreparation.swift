import Foundation

/// Activation is only a request. Playback may proceed only after the target is
/// observed in front; bounded retries never turn an unverified request into success.
public struct PlaybackForegroundPreparation: Sendable {
    public var request: @Sendable () async -> Void
    public var isReady: @Sendable () async -> Bool
    public var sleep: @Sendable () async throws -> Void

    public init(request: @escaping @Sendable () async -> Void,
                isReady: @escaping @Sendable () async -> Bool,
                sleep: @escaping @Sendable () async throws -> Void) {
        self.request = request; self.isReady = isReady; self.sleep = sleep
    }

    public func prepare(attempts: Int = 20) async -> Bool {
        for attempt in 0..<max(0, attempts) {
            guard !Task.isCancelled else { return false }
            await request()
            guard !Task.isCancelled else { return false }
            if await isReady() { return true }
            if attempt + 1 < attempts {
                do { try await sleep() } catch { return false }
            }
        }
        return false
    }
}
