import Foundation
import SwiftData
import SwiftRepoCore

/// A saved, runnable toolchain composition (identity + flags + layered presets/mixins + overrides).
@Model
final class ToolchainRecipe {
    @Attribute(.unique) var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    /// The full `ToolchainRecipeDraft`, JSON-encoded.
    public var draftJSON: Data

    public var draft: ToolchainRecipeDraft {
        get {
            var value = (try? JSONDecoder().decode(ToolchainRecipeDraft.self, from: draftJSON)) ?? ToolchainRecipeDraft()
            value.recipeID = id
            return value
        }
        set {
            draftJSON = (try? JSONEncoder().encode(newValue)) ?? Data()
            name = newValue.name
            updatedAt = .now
        }
    }

    public init(draft: ToolchainRecipeDraft) {
        self.id = draft.recipeID ?? UUID()
        self.name = draft.name
        self.createdAt = .now
        self.updatedAt = .now
        self.draftJSON = (try? JSONEncoder().encode(draft)) ?? Data()
    }
}


