import Foundation

nonisolated final class AsyncOneShotSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var didSignal = false

    public var isSignaled: Bool {
        lock.withLock { didSignal }
    }

    public var stream: AsyncStream<Void> {
        AsyncStream(Void.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            let shouldReplay = lock.withLock {
                guard !didSignal else { return true }
                continuations[id] = continuation
                return false
            }

            if shouldReplay {
                continuation.yield(())
                continuation.finish()
            }

            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id)
            }
        }
    }

    public func signal() {
        let currentContinuations = lock.withLock {
            guard !didSignal else { return [AsyncStream<Void>.Continuation]() }
            didSignal = true
            let current = Array(continuations.values)
            continuations.removeAll()
            return current
        }

        for continuation in currentContinuations {
            continuation.yield(())
            continuation.finish()
        }
    }

    private func removeContinuation(_ id: UUID) {
        lock.withLock {
            continuations[id] = nil
        }
    }
}
