import CompositionalInit
import Foundation
import SwiftXState

nonisolated enum AppSectionID: String, StateIdentifying, CaseIterable, Identifiable, Codable {
    case build
    case settings
    case history
    case logs
    case inspector

    var id: String { rawValue }
    static var _blank: AppSectionID { .build }

    var title: String {
        switch self {
        case .build: String(localized: "Build")
        case .settings: String(localized: "Settings")
        case .history: String(localized: "History")
        case .logs: String(localized: "Logs")
        case .inspector: String(localized: "Inspector")
        }
    }

    var symbolName: String {
        switch self {
        case .build: "hammer"
        case .settings: "slider.horizontal.3"
        case .history: "clock.arrow.circlepath"
        case .logs: "doc.text"
        case .inspector: "waveform.path.ecg.rectangle"
        }
    }

    var next: AppSectionID {
        let sections = Self.allCases
        guard let index = sections.firstIndex(of: self) else { return .build }
        return sections[sections.index(after: index) == sections.endIndex ? sections.startIndex : sections.index(after: index)]
    }

    var previous: AppSectionID {
        let sections = Self.allCases
        guard let index = sections.firstIndex(of: self) else { return .build }
        if index == sections.startIndex {
            return sections[sections.index(before: sections.endIndex)]
        }
        return sections[sections.index(before: index)]
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
