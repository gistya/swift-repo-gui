import SwiftXState

nonisolated enum ToolchainState: String, StateIdentifying {
    case loading
    case ready
    case failed
    static var _blank: ToolchainState { .loading }
}
