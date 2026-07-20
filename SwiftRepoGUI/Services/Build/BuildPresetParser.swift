import Foundation

/// A minimal parser for the subset of Python `configparser` syntax that `build-presets.ini` uses:
/// `[section]` headers, `key = value` / `key: value` / bare `key` (allow-no-value), indented
/// multi-line continuations, and `#` / `;` comments. Mirrors `presets.py._parse_raw_preset`.
nonisolated public enum BuildPresetParser {
    private static let sectionPrefix = "preset: "

    public static func parse(contentsOf url: URL) throws -> [ParsedPreset] {
        parse(try String(contentsOf: url, encoding: .utf8))
    }

    /// Scan the user's home directory for `*.ini` files and return every `[preset: …]` section they
    /// define, sorted by file name. A file that isn't in build-presets format has no `preset:` sections,
    /// so it parses to nothing and is skipped — this only surfaces real toolchain preset files, e.g. the
    /// `~/<tag>-presets.ini` overlays SwiftBuilder writes when it builds a toolchain. Unreadable files
    /// are ignored rather than failing the whole scan.
    public static func homeDirectoryPresets(
        in homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> [ParsedPreset] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: homeDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }
        // Dedupe by preset name across files (several overlays generated with the same prefix+flags can
        // share a name); the first file wins, scanned in file-name order.
        var seen = Set<String>()
        return entries
            .filter { $0.pathExtension.lowercased() == "ini" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .flatMap { (try? parse(contentsOf: $0)) ?? [] }
            .filter { seen.insert($0.name).inserted }
    }

    public static func parse(_ text: String) -> [ParsedPreset] {
        var sections: [(name: String, keys: [(String, String?)])] = []
        var currentSection: (name: String, keys: [(String, String?)])?
        var currentKey: String?

        func flush() {
            if let currentSection { sections.append(currentSection) }
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank lines and comments end nothing but a continuation.
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }

            // Section header.
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                flush()
                let inner = String(trimmed.dropFirst().dropLast())
                currentSection = (name: inner, keys: [])
                currentKey = nil
                continue
            }

            // Indented continuation of the previous key's (multi-line) value.
            let isIndented = line.first == " " || line.first == "\t"
            if isIndented, currentKey != nil, var section = currentSection {
                if let idx = section.keys.lastIndex(where: { $0.0 == currentKey }) {
                    let existing = section.keys[idx].1 ?? ""
                    section.keys[idx].1 = existing.isEmpty ? trimmed : existing + "\n" + trimmed
                    currentSection = section
                }
                continue
            }

            guard currentSection != nil else { continue }

            // key = value | key: value | bare key
            let (key, value) = splitKeyValue(trimmed)
            currentSection?.keys.append((key, value))
            currentKey = key
        }
        flush()

        return sections.compactMap { section in
            guard section.name.lowercased().hasPrefix(sectionPrefix) else { return nil }
            let name = String(section.name.dropFirst(sectionPrefix.count)).trimmingCharacters(in: .whitespaces)

            var mixins: [String] = []
            var options: [PresetOption] = []
            for (key, value) in section.keys {
                if key == "dash-dash" { continue }
                if key == "mixin-preset" {
                    let refs = (value ?? "")
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    mixins.append(contentsOf: refs)
                    continue
                }
                let cleanValue = value.flatMap { $0.isEmpty ? nil : $0 }
                options.append(PresetOption(name: key, value: cleanValue))
            }
            return ParsedPreset(name: name, mixins: mixins, options: options)
        }
    }

    private static func splitKeyValue(_ line: String) -> (String, String?) {
        // Prefer '=' but fall back to ':' (configparser accepts both); bare key otherwise.
        for separator in ["=", ":"] {
            if let range = line.range(of: separator) {
                let key = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                return (key, value)
            }
        }
        return (line, nil)
    }
}




