import Foundation
import SwiftData

/// A saved, runnable toolchain composition (identity + flags + layered presets/mixins + overrides).
@Model
final class ToolchainRecipe {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    /// The full `ToolchainRecipeDraft`, JSON-encoded.
    var draftJSON: Data

    var draft: ToolchainRecipeDraft {
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

    init(draft: ToolchainRecipeDraft) {
        self.id = draft.recipeID ?? UUID()
        self.name = draft.name
        self.createdAt = .now
        self.updatedAt = .now
        self.draftJSON = (try? JSONEncoder().encode(draft)) ?? Data()
    }
}

/// A user-defined preset/mixin building block that joins the built-in catalog as a composition unit.
@Model
final class CustomPreset {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var mixins: [String]
    var optionLines: [String]

    var value: CustomPresetValue {
        CustomPresetValue(id: id, name: name, mixins: mixins, optionLines: optionLines)
    }

    init(name: String, mixins: [String] = [], optionLines: [String] = []) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
        self.mixins = mixins
        self.optionLines = optionLines
    }

    func apply(_ value: CustomPresetValue) {
        name = value.name
        mixins = value.mixins
        optionLines = value.optionLines
        updatedAt = .now
    }
}
