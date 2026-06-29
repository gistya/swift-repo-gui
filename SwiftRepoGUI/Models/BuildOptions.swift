import Foundation

nonisolated struct BuildOptions: Codable, Equatable, Hashable, Sendable {
    var release = false
    var releaseDebugInfo = true
    var debug = false
    var minSizeRelease = false
    var clean = false
    var reconfigure = false
    var assertions = true
    var noAssertions = false
    var debugSwift = false
    var debugSwiftStdlib = false
    var debugLLVM = false
    var skipBuildOSXStdlib = false
    var skipBuildIOS = true
    var skipBuildBenchmarks = true
    var skipTests = true
    var validationTests = false
    var test = false
    var jobs: Int = ProcessInfo.processInfo.activeProcessorCount
    var litJobs: Int = 0
    var sccache = false
    var distcc = false
    var enableCaching = false
    var lto = false
    var ltoThin = false
    var enableASAN = false
    var enableUBSAN = false
    var enableTSAN = false
    var verboseBuild = false
    var dryRun = false
    var buildNinja = false
    var useMake = false
    var swiftPM = false
    var llbuild = false
    var lldb = false
    var swiftDriver = false
    var swiftTesting = false
    var installSwift = false
    var installLLVM = false
    var installSwiftPM = false
    var swiftDarwinSupportedArchs = ""
    var swiftDisableDeadStripping = true
    var buildSubdir = ""
    var preset = ""
    var extraArguments = ""

    static let `default` = BuildOptions()

    mutating func applyPreset(_ name: String) {
        preset = name
        switch name {
        case "developer-macos":
            releaseDebugInfo = true
            assertions = true
            skipBuildBenchmarks = true
            skipBuildIOS = true
            skipTests = true
            swiftDisableDeadStripping = true
            swiftDarwinSupportedArchs = ""
        case "buildbot_incremental":
            preset = "buildbot_incremental"
        case "release":
            release = true
            releaseDebugInfo = false
            debug = false
        case "debug-swift-tools":
            release = true
            debugSwift = true
            skipBuildOSXStdlib = true
        default:
            break
        }
    }
}

struct BuildOptionDescriptor: Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let practicalAdvice: String
    let category: BuildOptionCategory
}

enum BuildOptionCategory: String, CaseIterable, Identifiable {
    case buildMode
    case swiftComponents
    case platformTargets
    case performance
    case sanitizers
    case testing
    case installation
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .buildMode: "Build Mode"
        case .swiftComponents: "Swift Components"
        case .platformTargets: "Platform Targets"
        case .performance: "Performance"
        case .sanitizers: "Sanitizers"
        case .testing: "Testing"
        case .installation: "Installation"
        case .advanced: "Advanced"
        }
    }
}

enum BuildOptionCatalog {
    static let all: [BuildOptionDescriptor] = [
        BuildOptionDescriptor(
            id: "release",
            title: "Release (-R)",
            summary: "Optimize LLVM, Clang, and Swift for speed.",
            practicalAdvice: "Use for day-to-day compiler hacking when you want fast compiles and a toolchain that behaves like production. Pair with --debug-swift if you need to lldb into swiftc itself.",
            category: .buildMode
        ),
        BuildOptionDescriptor(
            id: "releaseDebugInfo",
            title: "RelWithDebInfo (-r)",
            summary: "Optimized build that still keeps debug symbols.",
            practicalAdvice: "This is the sweet spot for most macOS Swift contributors: fast enough to iterate, debuggable enough for lldb backtraces. GettingStarted.md recommends this as the default starting point.",
            category: .buildMode
        ),
        BuildOptionDescriptor(
            id: "debug",
            title: "Debug (-d)",
            summary: "Build everything without optimizations.",
            practicalAdvice: "Slow compiles and huge artifacts, but the easiest configuration for stepping through LLVM and Swift in a debugger. Reach for this when you're chasing a nasty codegen or SIL bug.",
            category: .buildMode
        ),
        BuildOptionDescriptor(
            id: "clean",
            title: "Clean (-c)",
            summary: "Wipe build products before building.",
            practicalAdvice: "Necessary when CMake caches get confused, after major branch switches, or when you suspect stale object files. Expect a from-scratch build time hit.",
            category: .buildMode
        ),
        BuildOptionDescriptor(
            id: "reconfigure",
            title: "Reconfigure",
            summary: "Re-run CMake for all subprojects during the build.",
            practicalAdvice: "Turn this on after editing CMakeLists, toggling feature flags, or pulling build-script changes. Without it, option changes may silently not apply.",
            category: .buildMode
        ),
        BuildOptionDescriptor(
            id: "assertions",
            title: "Assertions (-a)",
            summary: "Enable internal asserts across LLVM and Swift.",
            practicalAdvice: "Keep this on while developing the compiler. Assertions catch invalid invariants early instead of letting you chase miscompiles for hours.",
            category: .buildMode
        ),
        BuildOptionDescriptor(
            id: "debugSwift",
            title: "Debug Swift Tools",
            summary: "Build swiftc/swift-frontend without optimizations.",
            practicalAdvice: "The classic frontend workflow: optimized LLVM for speed, debuggable Swift tools for lldb. Much faster than a full debug build when you're only editing lib/AST or lib/Sema.",
            category: .swiftComponents
        ),
        BuildOptionDescriptor(
            id: "debugSwiftStdlib",
            title: "Debug Standard Library",
            summary: "Build the stdlib in debug mode even if tools are optimized.",
            practicalAdvice: "Useful when debugging runtime or stdlib behavior without paying the cost of a fully unoptimized compiler.",
            category: .swiftComponents
        ),
        BuildOptionDescriptor(
            id: "debugLLVM",
            title: "Debug LLVM",
            summary: "Build LLVM/Clang without optimizations.",
            practicalAdvice: "Reach for this when working in llvm-project itself. Otherwise leave LLVM optimized so your Swift rebuilds stay snappy.",
            category: .swiftComponents
        ),
        BuildOptionDescriptor(
            id: "skipBuildOSXStdlib",
            title: "Skip macOS Stdlib",
            summary: "Don't rebuild the macOS standard library.",
            practicalAdvice: "This is how you get a fast frontend-only iteration loop through build-script. You still need a prior stdlib build in the tree for many tests.",
            category: .swiftComponents
        ),
        BuildOptionDescriptor(
            id: "skipBuildIOS",
            title: "Skip iOS Stdlib",
            summary: "Don't build iOS standard library slices.",
            practicalAdvice: "Saves a lot of time on macOS-only compiler work. Turn off if you're touching availability, ABI, or platform-specific stdlib code.",
            category: .platformTargets
        ),
        BuildOptionDescriptor(
            id: "skipBuildBenchmarks",
            title: "Skip Benchmarks",
            summary: "Don't build the Swift benchmark suite.",
            practicalAdvice: "Almost always leave this on unless you're actively working on performance benchmarks.",
            category: .platformTargets
        ),
        BuildOptionDescriptor(
            id: "jobs",
            title: "Parallel Jobs (-j)",
            summary: "Number of concurrent compile/link tasks.",
            practicalAdvice: "Match your physical core count. Going far above that usually thrashes memory on large Swift link steps without much gain.",
            category: .performance
        ),
        BuildOptionDescriptor(
            id: "sccache",
            title: "Sccache",
            summary: "Cache C/C++/Swift compilation results across builds.",
            practicalAdvice: "Huge win after clean builds or branch switches if you have disk space. GettingStarted.md calls this out explicitly for repeat contributors.",
            category: .performance
        ),
        BuildOptionDescriptor(
            id: "distcc",
            title: "Distcc",
            summary: "Distribute compilation across machines.",
            practicalAdvice: "Only useful if you have a distcc farm configured. Irrelevant for most solo contributors.",
            category: .performance
        ),
        BuildOptionDescriptor(
            id: "enableCaching",
            title: "Clang/Swift Caching",
            summary: "Use clang-cache and swift cache-compile-job.",
            practicalAdvice: "Newer alternative to sccache integrated with recent toolchains. Mutually exclusive with sccache.",
            category: .performance
        ),
        BuildOptionDescriptor(
            id: "lto",
            title: "LTO",
            summary: "Link-time optimization for LLVM/Swift tools.",
            practicalAdvice: "Produces faster swiftc binaries but link steps become painfully slow. CI release builds use it; local iteration usually shouldn't.",
            category: .performance
        ),
        BuildOptionDescriptor(
            id: "enableASAN",
            title: "Address Sanitizer",
            summary: "Detect heap/stack memory errors at runtime.",
            practicalAdvice: "Essential when debugging use-after-free in the compiler. Expect 2-3x slowdown and much larger binaries.",
            category: .sanitizers
        ),
        BuildOptionDescriptor(
            id: "enableUBSAN",
            title: "UB Sanitizer",
            summary: "Trap on undefined behavior in C++ runtime code.",
            practicalAdvice: "Great for LLVM/Swift C++ layers. Can be combined with ASAN for especially paranoid debugging sessions.",
            category: .sanitizers
        ),
        BuildOptionDescriptor(
            id: "enableTSAN",
            title: "Thread Sanitizer",
            summary: "Detect data races in threaded compiler code.",
            practicalAdvice: "Use when working on concurrent driver or indexing code. Slower than ASAN and needs careful test selection.",
            category: .sanitizers
        ),
        BuildOptionDescriptor(
            id: "test",
            title: "Run Tests (-t)",
            summary: "Run the standard test suite after building.",
            practicalAdvice: "Good pre-PR validation. Can take a long time; use lit filtering from the command line for targeted runs.",
            category: .testing
        ),
        BuildOptionDescriptor(
            id: "validationTests",
            title: "Validation Tests (-T)",
            summary: "Also run the expensive validation test suite.",
            practicalAdvice: "CI-level thoroughness. Not something you want on every incremental frontend tweak.",
            category: .testing
        ),
        BuildOptionDescriptor(
            id: "swiftPM",
            title: "Build SwiftPM (-p)",
            summary: "Build the Swift Package Manager.",
            practicalAdvice: "Needed to actually use swift build/test with your fresh toolchain. GettingStarted adds this after the initial compiler build.",
            category: .installation
        ),
        BuildOptionDescriptor(
            id: "llbuild",
            title: "Build llbuild (-b)",
            summary: "Build Apple's low-level build engine used by SwiftPM.",
            practicalAdvice: "Required dependency for SwiftPM. If you're only rebuilding swift-frontend via ninja you can skip this.",
            category: .installation
        ),
        BuildOptionDescriptor(
            id: "lldb",
            title: "Build LLDB (-l)",
            summary: "Build the Swift-aware debugger.",
            practicalAdvice: "Only needed for debugger/lldb development. Adds significant build time.",
            category: .installation
        ),
        BuildOptionDescriptor(
            id: "swiftDriver",
            title: "Build Swift Driver",
            summary: "Build the swift-driver executable separately.",
            practicalAdvice: "Modern driver development lives in swift-driver repo. Enable when hacking driver behavior rather than frontend proper.",
            category: .installation
        ),
        BuildOptionDescriptor(
            id: "installSwift",
            title: "Install Swift",
            summary: "Stage swiftc and supporting tools into the toolchain prefix.",
            practicalAdvice: "Makes your freshly built compiler the one in toolchain-macosx-*/usr/bin. Needed for swiftpm and external package testing.",
            category: .installation
        ),
        BuildOptionDescriptor(
            id: "installLLVM",
            title: "Install LLVM",
            summary: "Stage clang/LLVM tools into the toolchain prefix.",
            practicalAdvice: "Pair with install-swift when you want a complete usable toolchain directory for xcrun-style workflows.",
            category: .installation
        ),
        BuildOptionDescriptor(
            id: "swiftDisableDeadStripping",
            title: "Disable Dead Stripping",
            summary: "Keep all symbols in Darwin host tools.",
            practicalAdvice: "GettingStarted recommends this on macOS so lldb always has symbols for optimized builds. Slightly larger binaries.",
            category: .advanced
        ),
        BuildOptionDescriptor(
            id: "verboseBuild",
            title: "Verbose Build",
            summary: "Print every compile and link command.",
            practicalAdvice: "Noisy but invaluable when you need to copy the exact swift-frontend invocation for reduce pipelines or Compiler Explorer repros.",
            category: .advanced
        ),
        BuildOptionDescriptor(
            id: "dryRun",
            title: "Dry Run (-n)",
            summary: "Print commands without executing them.",
            practicalAdvice: "Perfect for verifying what build-script will do before kicking off a multi-hour build.",
            category: .advanced
        ),
        BuildOptionDescriptor(
            id: "preset",
            title: "Preset",
            summary: "Use a named configuration from build-presets.ini.",
            practicalAdvice: "Presets are mutually exclusive with ad-hoc flags by design. Use them to exactly match CI bots like buildbot_incremental.",
            category: .advanced
        ),
        BuildOptionDescriptor(
            id: "buildSubdir",
            title: "Build Subdirectory",
            summary: "Place build products under a custom folder name.",
            practicalAdvice: "Lets you keep multiple configurations (asan, release, experimental) side by side without clobbering each other.",
            category: .advanced
        ),
        BuildOptionDescriptor(
            id: "extraArguments",
            title: "Extra Arguments",
            summary: "Pass through arbitrary flags to build-script.",
            practicalAdvice: "Escape hatch for flags not yet exposed in the UI. One flag per line.",
            category: .advanced
        ),
    ]

    static func descriptor(for id: String) -> BuildOptionDescriptor? {
        all.first { $0.id == id }
    }
}