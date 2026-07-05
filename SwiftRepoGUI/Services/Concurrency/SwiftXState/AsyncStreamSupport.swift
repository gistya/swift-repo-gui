import Foundation
import SwiftXState
import SwiftXStateSwiftUI

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
