import Foundation

/// A one-shot async signal: `fire()` resumes every current and future `wait()`. Fire-before-wait is
/// handled (the flag latches), so a process that exits before we suspend is never lost.
nonisolated public final class ProcessExitSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var hasFired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public func fire() {
        let toResume: [CheckedContinuation<Void, Never>]
        lock.lock()
        if hasFired {
            lock.unlock()
            return
        }
        hasFired = true
        toResume = waiters
        waiters = []
        lock.unlock()
        for continuation in toResume { continuation.resume() }
    }

    public func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if hasFired {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }
}
