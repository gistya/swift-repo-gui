import CompositionalInit
import Foundation

/// A user-defined preset/mixin building block — a reusable composition unit that joins the parsed
/// built-in catalog. Persisted as SwiftData `CustomPreset`.
nonisolated struct CustomPresetValue: Sendable, Equatable, Codable, Hashable, Identifiable, Blankable {
    var id: UUID = UUID()
    var name: String
    var mixins: [String] = []
    var optionLines: [String] = []

    /// Presented alongside built-in presets in the catalog.
    var asParsedPreset: ParsedPreset {
        ParsedPreset(
            name: name,
            mixins: mixins,
            options: optionLines.compactMap { PresetOption(parsing: $0) }
        )
    }
    
    static let _blank = Self(name: "")
}

extension PresetOption {
    /// Parse one option line ("release" or "compiler-vendor=apple") into an option.
    nonisolated init?(parsing line: String) {
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
