import CompositionalInit
import Foundation

/// A user-defined preset/mixin building block — a reusable composition unit that joins the parsed
/// built-in catalog. Persisted as SwiftData `CustomPreset`.
nonisolated public struct CustomPresetValue: Sendable, Equatable, Codable, Hashable, Identifiable, Blankable {
    public var id: UUID = UUID()
    public var name: String
    public var mixins: [String] = []
    public var optionLines: [String] = []
    
    public init(id: UUID = UUID(), name: String, mixins: [String] = [], optionLines: [String] = []) {
        self.id = id
        self.name = name
        self.mixins = mixins
        self.optionLines = optionLines
    }

    /// Presented alongside built-in presets in the catalog.
    public var asParsedPreset: ParsedPreset {
        ParsedPreset(
            name: name,
            mixins: mixins,
            options: optionLines.compactMap { PresetOption(parsing: $0) }
        )
    }
    
    public static let _blank = Self(name: "")
}

extension PresetOption {
    /// Parse one option line ("release" or "compiler-vendor=apple") into an option.
    nonisolated public init?(parsing line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let eq = trimmed.firstIndex(of: "=") {
            self.init(
                name: String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces),
                value: String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            )
        } else {
            self.init(name: trimmed, value: nil)
        }
    }
}
