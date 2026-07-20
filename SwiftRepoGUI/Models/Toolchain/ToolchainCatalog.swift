/// Sendable wrapper for the parsed preset catalog crossing the invoke boundary.
nonisolated public struct ToolchainCatalog: Sendable, Codable, Equatable {
    /// Presets parsed from the project's `build-presets.ini`.
    public var presets: [ParsedPreset]
    /// Presets discovered from `~/*.ini` overlay files, shown at the top of the "Your custom" menu.
    public var homePresets: [ParsedPreset] = []
}
