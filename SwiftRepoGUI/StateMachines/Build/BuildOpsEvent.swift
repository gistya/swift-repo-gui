import SwiftXState

nonisolated public enum BuildOpsEvent: EventIdentifying {
    case start(BuildJob)
    case startRequest(BuildRunRequest)
    case cancel
    case progressUpdated(BuildProgressSnapshot)
    case setStatusMessage(String)
    public static var _blank: BuildOpsEvent { .cancel }
}
