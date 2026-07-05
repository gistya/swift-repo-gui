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
            id: "buildNinja",
            title: "Build Ninja",
            summary: "Build Ninja before building Swift.",
            practicalAdvice: "Use when the checkout's bundled Ninja needs to be built or refreshed.",
            category: .buildMode
        ),
        BuildOptionDescriptor(
            id: "useMake",
            title: "Use Make",
            summary: "Generate Unix Makefiles instead of Ninja.",
            practicalAdvice: "Rare for local Swift development; most workflows should keep Ninja.",
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
            id: "litJobs",
            title: "lit Jobs",
            summary: "Number of concurrent lit test jobs.",
            practicalAdvice: "Leave at 0 for build-script defaults, or set explicitly when test scheduling needs to be capped.",
            category: .testing
        ),
        BuildOptionDescriptor(
            id: "installablePackage",
            title: "Installable Package",
            summary: "Build the installable toolchain package product.",
            practicalAdvice: "Use when you want a distributable toolchain artifact rather than only a local build tree.",
            category: .products
        ),
        BuildOptionDescriptor(
            id: "foundation",
            title: "Build Foundation",
            summary: "Build swift-foundation as part of the toolchain.",
            practicalAdvice: "Enable for package/toolchain workflows that need Foundation staged with the compiler.",
            category: .products
        ),
        BuildOptionDescriptor(
            id: "libDispatch",
            title: "Build libdispatch",
            summary: "Build dispatch support libraries.",
            practicalAdvice: "Usually paired with Foundation or complete toolchain builds.",
            category: .products
        ),
        BuildOptionDescriptor(
            id: "xctest",
            title: "Build XCTest",
            summary: "Build XCTest for the toolchain.",
            practicalAdvice: "Useful when validating packages or test workflows against the built toolchain.",
            category: .products
        ),
        BuildOptionDescriptor(
            id: "swiftDriver",
            title: "Build Swift Driver",
            summary: "Build the swift-driver executable separately.",
            practicalAdvice: "Modern driver development lives in swift-driver repo. Enable when hacking driver behavior rather than frontend proper.",
            category: .products
        ),
        BuildOptionDescriptor(
            id: "swiftTesting",
            title: "Build Swift Testing",
            summary: "Build the swift-testing package.",
            practicalAdvice: "Enable for toolchains that should include or validate the Swift Testing library.",
            category: .products
        ),
        BuildOptionDescriptor(
            id: "swiftTestingMacros",
            title: "Build Swift Testing Macros",
            summary: "Build the swift-testing macro support package.",
            practicalAdvice: "Pair with Swift Testing when producing an installable package.",
            category: .products
        ),
        BuildOptionDescriptor(
            id: "swiftSyntax",
            title: "Build SwiftSyntax",
            summary: "Build swift-syntax.",
            practicalAdvice: "Needed for syntax, macro, and tooling work that consumes the built toolchain.",
            category: .products
        ),
        BuildOptionDescriptor(
            id: "sourceKitLSP",
            title: "Build SourceKit-LSP",
            summary: "Build the language server.",
            practicalAdvice: "Enable for editor/tooling validation or complete developer toolchains.",
            category: .products
        ),
        BuildOptionDescriptor(
            id: "indexStoreDB",
            title: "Build IndexStoreDB",
            summary: "Build index database support.",
            practicalAdvice: "Usually needed by SourceKit-LSP and indexing workflows.",
            category: .products
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
            id: "installSwiftPM",
            title: "Install SwiftPM",
            summary: "Stage SwiftPM into the install tree.",
            practicalAdvice: "Enable with build SwiftPM when you want swift build/test available in the resulting toolchain.",
            category: .installation
        ),
        BuildOptionDescriptor(
            id: "installLLDB",
            title: "Install LLDB",
            summary: "Stage LLDB into the install tree.",
            practicalAdvice: "Pair with Build LLDB for debugger-capable toolchains.",
            category: .installation
        ),
        BuildOptionDescriptor(
            id: "installSwiftDriver",
            title: "Install Swift Driver",
            summary: "Stage swift-driver into the install tree.",
            practicalAdvice: "Enable when producing a usable toolchain package with the modern driver.",
            category: .installation
        ),
        BuildOptionDescriptor(
            id: "installSwiftTesting",
            title: "Install Swift Testing",
            summary: "Stage swift-testing into the install tree.",
            practicalAdvice: "Pair with Build Swift Testing for package/toolchain distribution.",
            category: .installation
        ),
        BuildOptionDescriptor(
            id: "installSwiftTestingMacros",
            title: "Install Swift Testing Macros",
            summary: "Stage swift-testing macros into the install tree.",
            practicalAdvice: "Use with Swift Testing when macro support should ship with the toolchain.",
            category: .installation
        ),
        BuildOptionDescriptor(
            id: "installSwiftSyntax",
            title: "Install SwiftSyntax",
            summary: "Stage swift-syntax into the install tree.",
            practicalAdvice: "Useful for macro and source tooling toolchains.",
            category: .installation
        ),
        BuildOptionDescriptor(
            id: "installSourceKitLSP",
            title: "Install SourceKit-LSP",
            summary: "Stage SourceKit-LSP into the install tree.",
            practicalAdvice: "Enable when producing a toolchain intended for editor integration.",
            category: .installation
        ),
        BuildOptionDescriptor(
            id: "installAll",
            title: "Install All",
            summary: "Install all selected built products.",
            practicalAdvice: "Useful for complete toolchain/package workflows; avoid for narrow frontend iteration.",
            category: .installation
        ),
        BuildOptionDescriptor(
            id: "swiftDarwinSupportedArchs",
            title: "Darwin Supported Archs",
            summary: "Value for --swift-darwin-supported-archs.",
            practicalAdvice: "On Apple Silicon this is often arm64 or the output of uname -m.",
            category: .deployment
        ),
        BuildOptionDescriptor(
            id: "hostTarget",
            title: "Host Target",
            summary: "Value for --host-target.",
            practicalAdvice: "For local Apple Silicon macOS builds this is commonly macosx-arm64.",
            category: .deployment
        ),
        BuildOptionDescriptor(
            id: "stdlibDeploymentTargets",
            title: "Stdlib Deployment Targets",
            summary: "Value for --stdlib-deployment-targets.",
            practicalAdvice: "Use space-separated targets such as macosx-arm64 when matching command-line recipes.",
            category: .deployment
        ),
        BuildOptionDescriptor(
            id: "buildStdlibDeploymentTargets",
            title: "Build Stdlib Deployment Targets",
            summary: "Value for --build-stdlib-deployment-targets.",
            practicalAdvice: "Narrow this when you want to build only specific stdlib deployment targets.",
            category: .deployment
        ),
        BuildOptionDescriptor(
            id: "buildSwiftDynamicStdlib",
            title: "Dynamic Swift Stdlib",
            summary: "Enable --build-swift-dynamic-stdlib.",
            practicalAdvice: "Useful for installable toolchains that need the dynamic standard library.",
            category: .deployment
        ),
        BuildOptionDescriptor(
            id: "buildSwiftDynamicSDKOverlay",
            title: "Dynamic SDK Overlay",
            summary: "Enable --build-swift-dynamic-sdk-overlay.",
            practicalAdvice: "Often paired with the dynamic stdlib for Darwin toolchains.",
            category: .deployment
        ),
        BuildOptionDescriptor(
            id: "buildSwiftStaticStdlib",
            title: "Static Swift Stdlib",
            summary: "Enable --build-swift-static-stdlib.",
            practicalAdvice: "Use for workflows that need static stdlib artifacts.",
            category: .deployment
        ),
        BuildOptionDescriptor(
            id: "buildSwiftStaticSDKOverlay",
            title: "Static SDK Overlay",
            summary: "Enable --build-swift-static-sdk-overlay.",
            practicalAdvice: "Use with static stdlib builds when static overlays are needed.",
            category: .deployment
        ),
        BuildOptionDescriptor(
            id: "installPrefix",
            title: "Install Prefix",
            summary: "Value for --install-prefix.",
            practicalAdvice: "Controls the prefix inside the staged toolchain.",
            category: .paths
        ),
        BuildOptionDescriptor(
            id: "installDestdir",
            title: "Install DESTDIR",
            summary: "Value for --install-destdir.",
            practicalAdvice: "Controls where install products are staged on disk.",
            category: .paths
        ),
        BuildOptionDescriptor(
            id: "installSymroot",
            title: "Install Symroot",
            summary: "Value for --install-symroot.",
            practicalAdvice: "Use when producing symbol/package artifacts.",
            category: .paths
        ),
        BuildOptionDescriptor(
            id: "darwinXCRunToolchain",
            title: "Darwin xcrun Toolchain",
            summary: "Value for --darwin-xcrun-toolchain.",
            practicalAdvice: "Override when build-script should use a specific Xcode toolchain.",
            category: .paths
        ),
        BuildOptionDescriptor(
            id: "cmake",
            title: "CMake Path",
            summary: "Value for --cmake.",
            practicalAdvice: "Point at a specific CMake executable when PATH resolution is not what you want.",
            category: .paths
        ),
        BuildOptionDescriptor(
            id: "hostCC",
            title: "Host C Compiler",
            summary: "Value for --host-cc.",
            practicalAdvice: "Use to override the C compiler used while configuring host tools.",
            category: .paths
        ),
        BuildOptionDescriptor(
            id: "hostCXX",
            title: "Host C++ Compiler",
            summary: "Value for --host-cxx.",
            practicalAdvice: "Use to override the C++ compiler used while configuring host tools.",
            category: .paths
        ),
        BuildOptionDescriptor(
            id: "llvmTargetsToBuild",
            title: "LLVM Targets",
            summary: "Value for --llvm-targets-to-build.",
            practicalAdvice: "Restrict LLVM targets to reduce build time or match a toolchain recipe.",
            category: .paths
        ),
        BuildOptionDescriptor(
            id: "buildArgs",
            title: "Build Args",
            summary: "Value for --build-args.",
            practicalAdvice: "Pass through build-system arguments accepted by build-script.",
            category: .paths
        ),
        BuildOptionDescriptor(
            id: "litArgs",
            title: "lit Args",
            summary: "Value for --lit-args.",
            practicalAdvice: "Use when running tests with extra lit filters or verbosity.",
            category: .paths
        ),
        BuildOptionDescriptor(
            id: "extraCMakeOptions",
            title: "Extra CMake Options",
            summary: "Value for --extra-cmake-options.",
            practicalAdvice: "For values containing spaces, enter them exactly as a shell argument value; the app will quote it for display and pass one process argument.",
            category: .paths
        ),
        BuildOptionDescriptor(
            id: "extraSwiftCMakeOptions",
            title: "Extra Swift CMake Options",
            summary: "Value for --extra-swift-cmake-options.",
            practicalAdvice: "Targets Swift-specific CMake configuration.",
            category: .paths
        ),
        BuildOptionDescriptor(
            id: "llvmCMakeOptions",
            title: "LLVM CMake Options",
            summary: "Value for --llvm-cmake-options.",
            practicalAdvice: "Targets LLVM CMake configuration.",
            category: .paths
        ),
        BuildOptionDescriptor(
            id: "extraLLVMCMakeOptions",
            title: "Extra LLVM CMake Options",
            summary: "Value for --extra-llvm-cmake-options.",
            practicalAdvice: "Additional LLVM-specific CMake options.",
            category: .paths
        ),
        BuildOptionDescriptor(
            id: "extraSwiftArgs",
            title: "Extra Swift Args",
            summary: "Value for --extra-swift-args.",
            practicalAdvice: "Pass extra arguments through to Swift build steps.",
            category: .paths
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
            practicalAdvice: "Escape hatch for flags not yet exposed in the UI. This field is shell-parsed, so quoted values and pasted multi-line snippets work.",
            category: .advanced
        ),
        BuildOptionDescriptor(
            id: "useCustomBuildScriptArguments",
            title: "Use Exact Build-Script Arguments",
            summary: "Ignore generated settings and run the pasted build-script arguments exactly.",
            practicalAdvice: "Use this when copying a known-good terminal command and you do not want the app's defaults added.",
            category: .advanced
        ),
        BuildOptionDescriptor(
            id: "customBuildScriptArguments",
            title: "Exact Build-Script Command",
            summary: "Paste a full build-script command or only its arguments.",
            practicalAdvice: "The app strips a leading build-script path if present and shell-parses quotes/backslash continuations.",
            category: .advanced
        ),
    ]

    static func descriptor(for id: String) -> BuildOptionDescriptor? {
        all.first { $0.id == id }
    }
}
