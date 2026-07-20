import Foundation

/// A `build-toolchain` flag that also shifts the composed preset name (see `build-toolchain`:
/// `--preset="${PRESET_PREFIX}buildbot_osx_package${NO_ASSERTIONS}${NO_TEST}${USE_OS_RUNTIME}${MACOS_ONLY}"`).
nonisolated public enum ToolchainFlag: String, CaseIterable, Codable, Sendable, Identifiable {
    case runTests          // -t : drops the ,no_test suffix
    case noAssertions      // -a : adds ,no_assertions
    case macosOnly         // --macos-only : adds ,macos_only
    case useOSRuntime      // --use-os-runtime : adds ,use_os_runtime
    case sccache           // --sccache (build speed, does not affect the name)
    case distcc            // --distcc (build speed, does not affect the name)
    case dryRun            // -n

    public var id: String { rawValue }

    /// Whether the flag changes which preset name build-toolchain resolves to.
    public var affectsPresetName: Bool {
        switch self {
        case .runTests, .noAssertions, .macosOnly, .useOSRuntime: true
        case .sccache, .distcc, .dryRun: false
        }
    }

    public var title: String {
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
    public var argument: String {
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
