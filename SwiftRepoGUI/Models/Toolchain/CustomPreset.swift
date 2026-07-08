import Foundation
import SwiftData
import SwiftRepoCore

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
