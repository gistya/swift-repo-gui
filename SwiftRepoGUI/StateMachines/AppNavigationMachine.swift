import CompositionalInit
import Foundation
import SwiftXState

nonisolated enum AppSectionID: String, StateIdentifying, CaseIterable, Identifiable {
    case build
    case settings
    case history
    case logs

    var id: String { rawValue }
    static var _blank: AppSectionID { .build }

    var title: String {
        switch self {
        case .build: "Build"
        case .settings: "Settings"
        case .history: "History"
        case .logs: "Logs"
        }
    }

    var symbolName: String {
        switch self {
        case .build: "hammer"
        case .settings: "slider.horizontal.3"
        case .history: "clock.arrow.circlepath"
        case .logs: "doc.text"
        }
    }
}

nonisolated enum AppNavigationEvent: EventIdentifying {
    case select(AppSectionID)
    static var _blank: AppNavigationEvent { .select(.build) }
}

nonisolated struct AppNavigationContext: Sendable, Equatable {
    var section: AppSectionID = .build
}

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
        XState(.ready) {
            XTransition(on: AppNavigationEvent.select, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .select(section)? = args.event { ctx.section = section }
                return ctx
            }
        }
        .initial()
    }
}