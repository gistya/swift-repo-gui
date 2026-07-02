import Foundation
import SwiftXState
import SwiftXStateSwiftUI

/// Thread-safe holder for a SwiftXState `Subscription` whose creation is asynchronous: if the stream
/// cancels before the actor subscription lands, it is cancelled the moment it arrives.
nonisolated private final class ActorSubscriptionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var subscription: SwiftXState.Subscription?
    private var cancelled = false

    func store(_ subscription: SwiftXState.Subscription) {
        let cancelNow: Bool = lock.withLock {
            if cancelled { return true }
            self.subscription = subscription
            return false
        }
        if cancelNow { subscription.cancel() }
    }

    func cancel() {
        let sub: SwiftXState.Subscription? = lock.withLock {
            cancelled = true
            let current = subscription
            subscription = nil
            return current
        }
        sub?.cancel()
    }
}

extension MachineStore {
    /// The machine actor's snapshots as an AsyncStream of the typed `(configuration, context)` pair.
    /// Each caller opens its own actor subscription. The actor replays the current snapshot on
    /// attach, so a transition cannot fall between "read state" and "subscribe".
    var snapshots: AsyncStream<(configuration: Configuration<M.StateID>?, context: M.Context)> {
        let actor = self.actor
        return AsyncStream(
            (configuration: Configuration<M.StateID>?, context: M.Context).self,
            bufferingPolicy: .bufferingNewest(64)
        ) { continuation in
            let box = ActorSubscriptionBox()
            let task = Task {
                let subscription = await actor.subscribe { configuration, context in
                    continuation.yield((configuration: configuration, context: context))
                }
                box.store(subscription)
            }

            continuation.onTermination = { _ in
                task.cancel()
                box.cancel()
            }
        }
    }

    func snapshots(
        timeout: Duration,
        timeoutError: @escaping @Sendable () -> any Error
    ) -> AsyncThrowingStream<(configuration: Configuration<M.StateID>?, context: M.Context), any Error> {
        let actor = self.actor
        return AsyncThrowingStream(
            (configuration: Configuration<M.StateID>?, context: M.Context).self,
            bufferingPolicy: .bufferingNewest(64)
        ) { continuation in
            let box = ActorSubscriptionBox()
            let subscriptionTask = Task {
                let subscription = await actor.subscribe { configuration, context in
                    continuation.yield((configuration: configuration, context: context))
                }
                box.store(subscription)
            }
            let timeoutTask = Task {
                do {
                    try await Task.sleep(for: timeout)
                    continuation.finish(throwing: timeoutError())
                    box.cancel()
                    subscriptionTask.cancel()
                } catch {
                    // Cancelled by normal stream termination.
                }
            }

            continuation.onTermination = { _ in
                subscriptionTask.cancel()
                timeoutTask.cancel()
                box.cancel()
            }
        }
    }
}

extension MachineActor {
    nonisolated var snapshots: AsyncStream<(configuration: Configuration<M.StateID>?, context: M.Context)> {
        let actor = self
        return AsyncStream(
            (configuration: Configuration<M.StateID>?, context: M.Context).self,
            bufferingPolicy: .bufferingNewest(64)
        ) { continuation in
            let box = ActorSubscriptionBox()
            let task = Task {
                let subscription = await actor.subscribe { configuration, context in
                    continuation.yield((configuration: configuration, context: context))
                }
                box.store(subscription)
            }

            continuation.onTermination = { _ in
                task.cancel()
                box.cancel()
            }
        }
    }
}
