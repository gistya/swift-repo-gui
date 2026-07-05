import SwiftXState

nonisolated enum ProjectState: String, StateIdentifying {
    case ready
    case loading
    case reloading
    case refreshing
    case error
    static var _blank: ProjectState { .ready }
}
