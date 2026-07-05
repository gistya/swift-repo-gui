import Foundation
import SwiftXState

struct AppNavigationMachine: StateMachine {
    typealias Context = AppNavigationContext
    typealias StateID = AppNavigationState
    typealias EventID = AppNavigationEvent

    nonisolated enum AppNavigationState: String, StateIdentifying {
        case ready
        static var _blank: AppNavigationState { .ready }
    }

    var context: AppNavigationContext { .init() }

    var machine: some XStateMachine {
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

nonisolated enum AppNavigationEvent: EventIdentifying {
    case select(AppSectionID)
    static var _blank: AppNavigationEvent { .select(.build) }
}

nonisolated struct AppNavigationContext: Sendable, Equatable {
    var section: AppSectionID = .build
}
