import Foundation

/// Thread-safe one-shot "stream finished" flag. `markFinished()` may be called
/// from any thread (buffer-completion queue, scheduler thread); `stream` emits exactly one `Void`
/// when the stream finishes and then completes — replaying immediately for a subscriber that attaches
/// after the fact, so there is no missed-event race.
nonisolated final class SoundtrackStreamFinishFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let signal = AsyncOneShotSignal()

    var isFinished: Bool {
        lock.withLock { finished }
    }

    var stream: AsyncStream<Void> { signal.stream }

    func markFinished() {
        let transitioned: Bool = lock.withLock {
            guard !finished else { return false }
            finished = true
            return true
        }
        if transitioned {
            signal.signal()
        }
    }
}
