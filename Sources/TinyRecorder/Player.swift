import Cocoa
import CoreGraphics
import Combine
import TinyRecorderCore

/// Replays a recorded macro by posting CGEvents at the original relative timestamps.
final class Player: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentLoop: Int = 0
    @Published private(set) var totalLoops: Int = 1

    private var task: Task<Void, Never>?
    /// Incremented on every play()/stop(). A task only touches published state
    /// if its generation still matches, so a stale epilogue can't clobber a
    /// newer playback that started right after stop().
    private var generation: UInt64 = 0
    private let pointResolver = PointResolver()

    /// Play the macro `loops` times. Pass `loops <= 0` for continuous (infinite) playback,
    /// which only stops on `stop()` or the configured stop hotkey.
    /// The completion receives `true` only when playback ran to natural completion —
    /// `false` for cancellation, so callers can skip chains/stats/sounds on abort.
    func play(events: [RecordedEvent], loops: Int = 1, speed: Double = 1.0, context: PlaybackContext = PlaybackContext(), completion: ((Bool) -> Void)? = nil) {
        guard !isPlaying, !events.isEmpty else { completion?(false); return }
        let infinite = (loops <= 0)
        let total = infinite ? 0 : max(1, loops)

        generation &+= 1
        let gen = generation
        isPlaying = true
        progress = 0
        currentLoop = 0
        totalLoops = total
        let speed = max(0.1, min(speed, 10.0))
        let lastTime = events.last?.time ?? 0

        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var loopIndex = 0
            // Throttle progress updates to ~30 Hz so the hot posting loop never
            // waits on a busy main thread between events.
            var lastProgressPush = 0.0
            outer: while !Task.isCancelled {
                if !infinite, loopIndex >= total { break }
                loopIndex += 1
                let snapshot = loopIndex
                await MainActor.run {
                    if self.generation == gen { self.currentLoop = snapshot }
                }
                let wallStart = CFAbsoluteTimeGetCurrent()
                for event in events {
                    if Task.isCancelled { break outer }
                    let target = wallStart + (event.time / speed)
                    let now = CFAbsoluteTimeGetCurrent()
                    let delay = target - now
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    if Task.isCancelled { break outer }
                    let point = self.pointResolver.resolve(event, context: context)
                    Player.post(event, at: point)
                    let postTime = CFAbsoluteTimeGetCurrent()
                    if lastTime > 0, postTime - lastProgressPush > 0.033 {
                        lastProgressPush = postTime
                        let frac = min(1.0, event.time / lastTime)
                        await MainActor.run {
                            if self.generation == gen { self.progress = frac }
                        }
                    }
                }
            }
            await MainActor.run {
                // Evaluate on the main actor so it's serialized with stop().
                let finished = !Task.isCancelled
                if self.generation == gen {
                    self.isPlaying = false
                    self.progress = 0
                    self.currentLoop = 0
                    self.totalLoops = 1
                }
                completion?(finished)
            }
        }
    }

    func stop() {
        generation &+= 1
        task?.cancel()
        task = nil
        isPlaying = false
        progress = 0
        currentLoop = 0
        totalLoops = 1
    }

    /// Synchronous playback for CLI mode — no MainActor hops, no published state.
    /// Blocks the calling (background) thread until done.
    static func playSynchronously(events: [RecordedEvent], loops: Int, speed: Double, context: PlaybackContext = PlaybackContext()) {
        guard !events.isEmpty else { return }
        let speed = max(0.1, min(speed, 10.0))
        let total = max(1, loops)
        let resolver = PointResolver()
        for _ in 0..<total {
            let wallStart = CFAbsoluteTimeGetCurrent()
            for event in events {
                let target = wallStart + (event.time / speed)
                let delay = target - CFAbsoluteTimeGetCurrent()
                if delay > 0 {
                    Thread.sleep(forTimeInterval: delay)
                }
                let point = resolver.resolve(event, context: context)
                Player.post(event, at: point)
            }
        }
    }

    // MARK: - Posting

    private static let synthesizer = MouseKeyboardSynthesizer()

    private static func post(_ ev: RecordedEvent, at point: CGPoint) {
        synthesizer.synthesize(ev, at: point)
    }
}
