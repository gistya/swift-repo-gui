import Foundation
import SwiftXState

public struct AppNavigationMachine: StateMachine {
    public typealias Context = AppNavigationContext
    public typealias StateID = AppNavigationState
    public typealias EventID = AppNavigationEvent
    
    public init() {}

    nonisolated public enum AppNavigationState: String, StateIdentifying {
        case ready
        public static var _blank: AppNavigationState { .ready }
    }

    public var context: AppNavigationContext { .init() }

    public var machine: some XStateMachine {
        State(.ready) {
            Transition(on: AppNavigationEvent.select, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .select(section)? = args.event { ctx.section = section }
                return ctx
            }
        }
        .initial()
    }
}

nonisolated public enum AppNavigationEvent: EventIdentifying {
    case select(AppSectionID)
    public static var _blank: AppNavigationEvent { .select(.build) }
}

nonisolated public struct AppNavigationContext: Sendable, Equatable {
    public var section: AppSectionID = .build
}
