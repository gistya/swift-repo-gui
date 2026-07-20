import SwiftXState

nonisolated public enum BuildSettingsState: String, StateIdentifying {
    case ready
    public static var _blank: BuildSettingsState { .ready }
}
