import Foundation

nonisolated final class SoundtrackStreamFinishFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    var isFinished: Bool {
        lock.withLock { finished }
    }

    func markFinished() {
        lock.withLock {
            finished = true
        }
    }
}
