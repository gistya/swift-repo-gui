import SwiftXState

nonisolated public enum BuildSettingsEvent: EventIdentifying {
    case setOptions(BuildOptions)
    case setRepository(String)
    case setBoolOption(key: String, value: Bool)
    case setIntOption(key: String, value: Int)
    case setStringOption(key: String, value: String)
    case applyPreset(String)
    case restore(BuildOptions, String)
    public static var _blank: BuildSettingsEvent { .setOptions(.default) }
}
