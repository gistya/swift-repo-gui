import Foundation
import SwiftXState

/// Thread-safe holder for a SwiftXState `Subscription` whose creation is asynchronous: if the stream
/// cancels before the actor subscription lands, it is cancelled the moment it arrives.
nonisolated public final class ActorSubscriptionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var subscription: SwiftXState.Subscription?
    private var cancelled = false
    
    public init(subscription: SwiftXState.Subscription? = nil, cancelled: Bool = false) {
        self.subscription = subscription
        self.cancelled = cancelled
    }

    public func store(_ subscription: SwiftXState.Subscription) {
        let cancelNow: Bool = lock.withLock {
            if cancelled { return true }
            self.subscription = subscription
            return false
        }
        if cancelNow { subscription.cancel() }
    }

    public func cancel() {
        let sub: SwiftXState.Subscription? = lock.withLock {
            cancelled = true
            let current = subscription
            subscription = nil
            return current
        }
        sub?.cancel()
    }
}
