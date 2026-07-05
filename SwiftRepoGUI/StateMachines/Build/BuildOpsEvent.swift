import SwiftXState

nonisolated enum BuildOpsEvent: EventIdentifying {
    case start(BuildJob)
    case startRequest(BuildRunRequest)
    case cancel
    case progressUpdated(BuildProgressSnapshot)
    case setStatusMessage(String)
    static var _blank: BuildOpsEvent { .cancel }
}
