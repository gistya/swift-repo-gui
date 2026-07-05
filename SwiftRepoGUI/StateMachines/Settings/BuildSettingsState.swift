import SwiftXState

nonisolated enum BuildSettingsState: String, StateIdentifying {
    case ready
    static var _blank: BuildSettingsState { .ready }
}
