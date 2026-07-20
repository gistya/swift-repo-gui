import Foundation

nonisolated public final class AsyncEventBroadcaster<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var didFinish = false

    public func stream(
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

    public func yield(_ makeValue: @Sendable () -> Element) {
        let currentContinuations = lock.withLock {
            didFinish ? [] : Array(continuations.values)
        }
        for continuation in currentContinuations {
            continuation.yield(makeValue())
        }
    }

    public func finish() {
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

