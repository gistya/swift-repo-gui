import Foundation
import SwiftXState

/// Thread-safe holder for a SwiftXState `Subscription` whose creation is asynchronous: if the stream
/// cancels before the actor subscription lands, it is cancelled the moment it arrives.
nonisolated final class ActorSubscriptionBox: @unchecked Sendable {
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
