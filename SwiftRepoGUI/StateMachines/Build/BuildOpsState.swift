import SwiftXState

nonisolated public enum BuildOpsState: String, StateIdentifying {
    case idle
    case running
    case building
    case testing
    case measuring
    case deploying
    case completed
    case error
    case cancelled
    public static var _blank: BuildOpsState { .idle }
}
