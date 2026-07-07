import Foundation
import SwiftXState

/// Which theme the app renders with. A tiny three-state machine so the appearance choice is a
/// first-class part of the statechart architecture (and shows up live in the Inspector) rather than a
/// loose flag. `AppSession` mirrors the selected state into `AppStyleStore.preview`, which the theme
/// system actually reads, and persists it across launches.
struct AppearanceMachine: StateMachine {
    typealias Context = AppearanceContext
    typealias StateID = AppearanceState
    typealias EventID = AppearanceEvent

    nonisolated enum AppearanceState: String, StateIdentifying {
        /// Follow the OS appearance.
        case system
        case dark
        case light
        static var _blank: AppearanceState { .system }
    }

    var context: AppearanceContext { .init() }

    var machine: some XStateMachine {
        State(.system) {
            Transition(on: AppearanceEvent.useDark, to: .dark)
            Transition(on: AppearanceEvent.useLight, to: .light)
        }
        .initial()

        State(.dark) {
            Transition(on: AppearanceEvent.useSystem, to: .system)
            Transition(on: AppearanceEvent.useLight, to: .light)
        }

        State(.light) {
            Transition(on: AppearanceEvent.useSystem, to: .system)
            Transition(on: AppearanceEvent.useDark, to: .dark)
        }
    }
}

nonisolated enum AppearanceEvent: EventIdentifying {
    case useSystem
    case useDark
    case useLight
    static var _blank: AppearanceEvent { .useSystem }
}

nonisolated struct AppearanceContext: Sendable, Equatable {}
