import SwiftXState

nonisolated struct ToolchainContext: Sendable, Equatable {
    var presetFilePath: String = ""
    var catalog: [ParsedPreset] = []
    var draft: ToolchainRecipeDraft = ToolchainRecipeDraft()
    var lastError: String?

    /// Composed presets (runnable) vs mixin building blocks — for the two catalog panes.
    var composedPresets: [ParsedPreset] { catalog.filter { !$0.isMixin }.sorted { $0.name < $1.name } }
    var mixinPresets: [ParsedPreset] { catalog.filter { $0.isMixin }.sorted { $0.name < $1.name } }
}
