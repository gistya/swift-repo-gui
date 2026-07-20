/// A single option line inside a `[preset: …]` section: a bare flag (`release`) or a key/value
/// (`compiler-vendor=apple`). Names are build-script long options WITHOUT the leading `--`.
nonisolated public struct PresetOption: Sendable, Hashable, Codable {
    public let name: String
    public let value: String?
    
    public init(name: String, value: String?) {
        self.name = name
        self.value = value
    }

    /// Render back to preset-file form.
    public var line: String { value.map { "\(name)=\($0)" } ?? name }

    /// Render as a build-script CLI argument (how `presets.py` expands it).
    public var argument: String { value.map { "--\(name)=\($0)" } ?? "--\(name)" }
}
