/// One `[preset: NAME]` section from a build-presets.ini file. `name` is the literal section name
/// (it can legally contain commas, e.g. `buildbot_osx_package,no_test`). `mixins` are the
/// `mixin-preset=` references (other preset names, expanded in order by `presets.py`).
nonisolated public struct ParsedPreset: Identifiable, Sendable, Hashable, Codable {
    public let name: String
    public let mixins: [String]
    public let options: [PresetOption]

    public var id: String { name }
    
    public init(name: String, mixins: [String], options: [PresetOption]) {
        self.name = name
        self.mixins = mixins
        self.options = options
    }

    /// The Swift build presets convention: reusable building blocks are named `mixin…`; everything
    /// else is a runnable/composed preset.
    public var isMixin: Bool { name.lowercased().hasPrefix("mixin") }
}
