import CompositionalInit
import Foundation

/// The in-flight toolchain composition the user is editing (the value the `ToolchainMachine` holds).
/// Persisted copies live in the SwiftData `ToolchainRecipe`.
nonisolated public struct ToolchainRecipeDraft: Sendable, Equatable, Codable, Hashable, Blankable {
    public var name: String = "My Toolchain"
    /// build-toolchain positional bundle tag (e.g. "gistya"). Names the .xctoolchain bundle id.
    public var bundleTag: String = "local"
    /// --preset-prefix (e.g. "gistya_"). Namespaces the generated override preset.
    public var presetPrefix: String = "local_"
    public var flags: Set<ToolchainFlag> = []
    /// Preset/mixin names (built-in OR custom) layered on top of the stock toolchain preset.
    public var selectedMixins: [String] = []
    /// Raw build-script long-option override lines (bare flag or key=value), applied last so they win.
    public var extraOptions: [String] = []

    public var recipeID: UUID? = nil

    public static let bundlePackage = "buildbot_osx_package"
    
    public init (name: String = "My Toolchain",
                 bundleTag: String = "local",
                 presetPrefix: String = "local_",
                 flags: Set<ToolchainFlag> = [],
                 selectedMixins: [String] = [],
                 extraOptions: [String] = [],
                 recipeID: UUID? = nil) {
        self.name = name
        self.bundleTag = bundleTag
        self.presetPrefix = presetPrefix
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.bundleTag = try container.decode(String.self, forKey: .bundleTag)
        self.presetPrefix = try container.decode(String.self, forKey: .presetPrefix)
        self.flags = try container.decode(Set<ToolchainFlag>.self, forKey: .flags)
        self.selectedMixins = try container.decode([String].self, forKey: .selectedMixins)
        self.extraOptions = try container.decode([String].self, forKey: .extraOptions)
        self.recipeID = try container.decodeIfPresent(UUID.self, forKey: .recipeID)
    }
    
    public static let _blank = Self(name: ._blank, bundleTag: ._blank, presetPrefix: ._blank, flags: [], selectedMixins: [], extraOptions: [], recipeID: nil)
}
