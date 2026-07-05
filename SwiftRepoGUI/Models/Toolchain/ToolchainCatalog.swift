/// Sendable wrapper for the parsed preset catalog crossing the invoke boundary.
nonisolated struct ToolchainCatalog: Sendable, Codable, Equatable {
    var presets: [ParsedPreset]
}
