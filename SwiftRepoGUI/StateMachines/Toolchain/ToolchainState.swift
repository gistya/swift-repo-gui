import SwiftXState

nonisolated public enum ToolchainState: String, StateIdentifying {
    case loading
    case ready
    case failed
    public static var _blank: ToolchainState { .loading }
}
