import SwiftXState

nonisolated public enum ProjectState: String, StateIdentifying {
    case ready
    case loading
    case reloading
    case refreshing
    case error
    public static var _blank: ProjectState { .ready }
}
