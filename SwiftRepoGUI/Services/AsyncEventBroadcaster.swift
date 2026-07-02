import Foundation

nonisolated final class AsyncEventBroadcaster<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var didFinish = false

    func stream(
        bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<Element> {
        AsyncStream(Element.self, bufferingPolicy: bufferingPolicy) { continuation in
            let id = UUID()
            let shouldFinish = lock.withLock {
                guard !didFinish else { return true }
                continuations[id] = continuation
                return false
            }

            if shouldFinish {
                continuation.finish()
            }

            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id)
            }
        }
    }

    func yield(_ makeValue: @Sendable () -> Element) {
        let currentContinuations = lock.withLock {
            didFinish ? [] : Array(continuations.values)
        }
        for continuation in currentContinuations {
            continuation.yield(makeValue())
        }
    }

    func finish() {
        let currentContinuations = lock.withLock {
            didFinish = true
            let current = Array(continuations.values)
            continuations.removeAll()
            return current
        }
        for continuation in currentContinuations {
            continuation.finish()
        }
    }

    private func removeContinuation(_ id: UUID) {
        lock.withLock {
            continuations[id] = nil
        }
    }
}

nonisolated final class AsyncOneShotSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var didSignal = false

    var isSignaled: Bool {
        lock.withLock { didSignal }
    }

    var stream: AsyncStream<Void> {
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

    func signal() {
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
