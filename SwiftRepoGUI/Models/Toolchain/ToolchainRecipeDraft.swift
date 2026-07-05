import CompositionalInit
import Foundation

/// The in-flight toolchain composition the user is editing (the value the `ToolchainMachine` holds).
/// Persisted copies live in the SwiftData `ToolchainRecipe`.
nonisolated struct ToolchainRecipeDraft: Sendable, Equatable, Codable, Hashable, Blankable {
    var name: String = "My Toolchain"
    /// build-toolchain positional bundle tag (e.g. "gistya"). Names the .xctoolchain bundle id.
    var bundleTag: String = "local"
    /// --preset-prefix (e.g. "gistya_"). Namespaces the generated override preset.
    var presetPrefix: String = "local_"
    var flags: Set<ToolchainFlag> = []
    /// Preset/mixin names (built-in OR custom) layered on top of the stock toolchain preset.
    var selectedMixins: [String] = []
    /// Raw build-script long-option override lines (bare flag or key=value), applied last so they win.
    var extraOptions: [String] = []

    var recipeID: UUID? = nil

    static let bundlePackage = "buildbot_osx_package"
    
    static let _blank = Self(name: ._blank, bundleTag: ._blank, presetPrefix: ._blank, flags: [], selectedMixins: [], extraOptions: [], recipeID: nil)
}
