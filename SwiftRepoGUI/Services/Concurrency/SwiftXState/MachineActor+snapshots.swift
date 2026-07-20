import SwiftXState

public extension MachineActor {
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
