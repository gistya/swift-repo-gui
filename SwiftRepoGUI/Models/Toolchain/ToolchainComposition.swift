import Foundation

/// A `build-toolchain` flag that also shifts the composed preset name (see `build-toolchain`:
/// `--preset="${PRESET_PREFIX}buildbot_osx_package${NO_ASSERTIONS}${NO_TEST}${USE_OS_RUNTIME}${MACOS_ONLY}"`).
nonisolated enum ToolchainFlag: String, CaseIterable, Codable, Sendable, Identifiable {
    case runTests          // -t : drops the ,no_test suffix
    case noAssertions      // -a : adds ,no_assertions
    case macosOnly         // --macos-only : adds ,macos_only
    case useOSRuntime      // --use-os-runtime : adds ,use_os_runtime
    case sccache           // --sccache (build speed, does not affect the name)
    case distcc            // --distcc (build speed, does not affect the name)
    case dryRun            // -n

    var id: String { rawValue }

    /// Whether the flag changes which preset name build-toolchain resolves to.
    var affectsPresetName: Bool {
        switch self {
        case .runTests, .noAssertions, .macosOnly, .useOSRuntime: true
        case .sccache, .distcc, .dryRun: false
        }
    }

    var title: String {
        switch self {
        case .runTests: "Run tests"
        case .noAssertions: "No assertions"
        case .macosOnly: "macOS only"
        case .useOSRuntime: "Link OS runtime"
        case .sccache: "sccache"
        case .distcc: "distcc"
        case .dryRun: "Dry run"
        }
    }

    /// The `build-toolchain` command-line flag.
    var argument: String {
        switch self {
        case .runTests: "--test"
        case .noAssertions: "--no-assert"
        case .macosOnly: "--macos-only"
        case .useOSRuntime: "--use-os-runtime"
        case .sccache: "--sccache"
        case .distcc: "--distcc"
        case .dryRun: "--dry-run"
        }
    }
}

/// The in-flight toolchain composition the user is editing (the value the `ToolchainMachine` holds).
/// Persisted copies live in the SwiftData `ToolchainRecipe`.
nonisolated struct ToolchainRecipeDraft: Sendable, Equatable, Codable, Hashable {
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
}

/// A user-defined preset/mixin building block — a reusable composition unit that joins the parsed
/// built-in catalog. Persisted as SwiftData `CustomPreset`.
nonisolated struct CustomPresetValue: Sendable, Equatable, Codable, Hashable, Identifiable {
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
