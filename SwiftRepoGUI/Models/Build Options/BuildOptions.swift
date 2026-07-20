import Foundation

nonisolated public struct BuildOptions: Codable, Equatable, Hashable, Sendable {
    public var release = false
    public var releaseDebugInfo = true
    public var debug = false
    public var minSizeRelease = false
    public var clean = false
    public var reconfigure = false
    public var assertions = true
    public var noAssertions = false
    public var debugSwift = false
    public var debugSwiftStdlib = false
    public var debugLLVM = false
    public var skipBuildOSXStdlib = false
    public var skipBuildIOS = true
    public var skipBuildBenchmarks = true
    public var skipTests = true
    public var validationTests = false
    public var test = false
    public var jobs: Int = ProcessInfo.processInfo.activeProcessorCount
    public var litJobs: Int = 0
    public var sccache = false
    public var distcc = false
    public var enableCaching = false
    public var lto = false
    public var ltoThin = false
    public var enableASAN = false
    public var enableUBSAN = false
    public var enableTSAN = false
    public var verboseBuild = false
    public var dryRun = false
    public var buildNinja = false
    public var useMake = false
    public var swiftPM = false
    public var llbuild = false
    public var lldb = false
    public var swiftDriver = false
    public var swiftTesting = false
    public var swiftTestingMacros = false
    public var swiftSyntax = false
    public var sourceKitLSP = false
    public var indexStoreDB = false
    public var foundation = false
    public var libDispatch = false
    public var xctest = false
    public var installablePackage = false
    /// Destination path for the `--installable-package` toolchain tarball. Empty = write into the
    /// app's Exports folder (see `BuildCommandBuilder`).
    public var installablePackagePath = ""
    public var installAll = false
    public var installSwift = false
    public var installLLVM = false
    public var installSwiftPM = false
    public var installLLDB = false
    public var installSwiftDriver = false
    public var installSwiftTesting = false
    public var installSwiftTestingMacros = false
    public var installSwiftSyntax = false
    public var installSourceKitLSP = false
    public var swiftDarwinSupportedArchs = ""
    public var hostTarget = ""
    public var stdlibDeploymentTargets = ""
    public var buildStdlibDeploymentTargets = ""
    public var swiftDisableDeadStripping = true
    public var buildSwiftDynamicStdlib = false
    public var buildSwiftDynamicSDKOverlay = false
    public var buildSwiftStaticStdlib = false
    public var buildSwiftStaticSDKOverlay = false
    public var buildSubdir = ""
    public var preset = ""
    public var installPrefix = ""
    public var installDestdir = ""
    public var installSymroot = ""
    public var darwinXCRunToolchain = ""
    public var cmake = ""
    public var hostCC = ""
    public var hostCXX = ""
    public var llvmTargetsToBuild = ""
    public var buildArgs = ""
    public var litArgs = ""
    public var extraCMakeOptions = ""
    public var extraSwiftCMakeOptions = ""
    public var llvmCMakeOptions = ""
    public var extraLLVMCMakeOptions = ""
    public var extraSwiftArgs = ""
    public var useCustomBuildScriptArguments = false
    public var customBuildScriptArguments = ""
    public var extraArguments = ""

    public static let `default` = BuildOptions()

    public init() {}

    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: BuildOptionsCodingKey.self)

        release = try container.decodeIfPresent("release", default: release)
        releaseDebugInfo = try container.decodeIfPresent("releaseDebugInfo", default: releaseDebugInfo)
        debug = try container.decodeIfPresent("debug", default: debug)
        minSizeRelease = try container.decodeIfPresent("minSizeRelease", default: minSizeRelease)
        clean = try container.decodeIfPresent("clean", default: clean)
        reconfigure = try container.decodeIfPresent("reconfigure", default: reconfigure)
        assertions = try container.decodeIfPresent("assertions", default: assertions)
        noAssertions = try container.decodeIfPresent("noAssertions", default: noAssertions)
        debugSwift = try container.decodeIfPresent("debugSwift", default: debugSwift)
        debugSwiftStdlib = try container.decodeIfPresent("debugSwiftStdlib", default: debugSwiftStdlib)
        debugLLVM = try container.decodeIfPresent("debugLLVM", default: debugLLVM)
        skipBuildOSXStdlib = try container.decodeIfPresent("skipBuildOSXStdlib", default: skipBuildOSXStdlib)
        skipBuildIOS = try container.decodeIfPresent("skipBuildIOS", default: skipBuildIOS)
        skipBuildBenchmarks = try container.decodeIfPresent("skipBuildBenchmarks", default: skipBuildBenchmarks)
        skipTests = try container.decodeIfPresent("skipTests", default: skipTests)
        validationTests = try container.decodeIfPresent("validationTests", default: validationTests)
        test = try container.decodeIfPresent("test", default: test)
        jobs = try container.decodeIfPresent("jobs", default: jobs)
        litJobs = try container.decodeIfPresent("litJobs", default: litJobs)
        sccache = try container.decodeIfPresent("sccache", default: sccache)
        distcc = try container.decodeIfPresent("distcc", default: distcc)
        enableCaching = try container.decodeIfPresent("enableCaching", default: enableCaching)
        lto = try container.decodeIfPresent("lto", default: lto)
        ltoThin = try container.decodeIfPresent("ltoThin", default: ltoThin)
        enableASAN = try container.decodeIfPresent("enableASAN", default: enableASAN)
        enableUBSAN = try container.decodeIfPresent("enableUBSAN", default: enableUBSAN)
        enableTSAN = try container.decodeIfPresent("enableTSAN", default: enableTSAN)
        verboseBuild = try container.decodeIfPresent("verboseBuild", default: verboseBuild)
        dryRun = try container.decodeIfPresent("dryRun", default: dryRun)
        buildNinja = try container.decodeIfPresent("buildNinja", default: buildNinja)
        useMake = try container.decodeIfPresent("useMake", default: useMake)
        swiftPM = try container.decodeIfPresent("swiftPM", default: swiftPM)
        llbuild = try container.decodeIfPresent("llbuild", default: llbuild)
        lldb = try container.decodeIfPresent("lldb", default: lldb)
        swiftDriver = try container.decodeIfPresent("swiftDriver", default: swiftDriver)
        swiftTesting = try container.decodeIfPresent("swiftTesting", default: swiftTesting)
        swiftTestingMacros = try container.decodeIfPresent("swiftTestingMacros", default: swiftTestingMacros)
        swiftSyntax = try container.decodeIfPresent("swiftSyntax", default: swiftSyntax)
        sourceKitLSP = try container.decodeIfPresent("sourceKitLSP", default: sourceKitLSP)
        indexStoreDB = try container.decodeIfPresent("indexStoreDB", default: indexStoreDB)
        foundation = try container.decodeIfPresent("foundation", default: foundation)
        libDispatch = try container.decodeIfPresent("libDispatch", default: libDispatch)
        xctest = try container.decodeIfPresent("xctest", default: xctest)
        installablePackage = try container.decodeIfPresent("installablePackage", default: installablePackage)
        installablePackagePath = try container.decodeIfPresent("installablePackagePath", default: installablePackagePath)
        installAll = try container.decodeIfPresent("installAll", default: installAll)
        installSwift = try container.decodeIfPresent("installSwift", default: installSwift)
        installLLVM = try container.decodeIfPresent("installLLVM", default: installLLVM)
        installSwiftPM = try container.decodeIfPresent("installSwiftPM", default: installSwiftPM)
        installLLDB = try container.decodeIfPresent("installLLDB", default: installLLDB)
        installSwiftDriver = try container.decodeIfPresent("installSwiftDriver", default: installSwiftDriver)
        installSwiftTesting = try container.decodeIfPresent("installSwiftTesting", default: installSwiftTesting)
        installSwiftTestingMacros = try container.decodeIfPresent("installSwiftTestingMacros", default: installSwiftTestingMacros)
        installSwiftSyntax = try container.decodeIfPresent("installSwiftSyntax", default: installSwiftSyntax)
        installSourceKitLSP = try container.decodeIfPresent("installSourceKitLSP", default: installSourceKitLSP)
        swiftDarwinSupportedArchs = try container.decodeIfPresent("swiftDarwinSupportedArchs", default: swiftDarwinSupportedArchs)
        hostTarget = try container.decodeIfPresent("hostTarget", default: hostTarget)
        stdlibDeploymentTargets = try container.decodeIfPresent("stdlibDeploymentTargets", default: stdlibDeploymentTargets)
        buildStdlibDeploymentTargets = try container.decodeIfPresent("buildStdlibDeploymentTargets", default: buildStdlibDeploymentTargets)
        swiftDisableDeadStripping = try container.decodeIfPresent("swiftDisableDeadStripping", default: swiftDisableDeadStripping)
        buildSwiftDynamicStdlib = try container.decodeIfPresent("buildSwiftDynamicStdlib", default: buildSwiftDynamicStdlib)
        buildSwiftDynamicSDKOverlay = try container.decodeIfPresent("buildSwiftDynamicSDKOverlay", default: buildSwiftDynamicSDKOverlay)
        buildSwiftStaticStdlib = try container.decodeIfPresent("buildSwiftStaticStdlib", default: buildSwiftStaticStdlib)
        buildSwiftStaticSDKOverlay = try container.decodeIfPresent("buildSwiftStaticSDKOverlay", default: buildSwiftStaticSDKOverlay)
        buildSubdir = try container.decodeIfPresent("buildSubdir", default: buildSubdir)
        preset = try container.decodeIfPresent("preset", default: preset)
        installPrefix = try container.decodeIfPresent("installPrefix", default: installPrefix)
        installDestdir = try container.decodeIfPresent("installDestdir", default: installDestdir)
        installSymroot = try container.decodeIfPresent("installSymroot", default: installSymroot)
        darwinXCRunToolchain = try container.decodeIfPresent("darwinXCRunToolchain", default: darwinXCRunToolchain)
        cmake = try container.decodeIfPresent("cmake", default: cmake)
        hostCC = try container.decodeIfPresent("hostCC", default: hostCC)
        hostCXX = try container.decodeIfPresent("hostCXX", default: hostCXX)
        llvmTargetsToBuild = try container.decodeIfPresent("llvmTargetsToBuild", default: llvmTargetsToBuild)
        buildArgs = try container.decodeIfPresent("buildArgs", default: buildArgs)
        litArgs = try container.decodeIfPresent("litArgs", default: litArgs)
        extraCMakeOptions = try container.decodeIfPresent("extraCMakeOptions", default: extraCMakeOptions)
        extraSwiftCMakeOptions = try container.decodeIfPresent("extraSwiftCMakeOptions", default: extraSwiftCMakeOptions)
        llvmCMakeOptions = try container.decodeIfPresent("llvmCMakeOptions", default: llvmCMakeOptions)
        extraLLVMCMakeOptions = try container.decodeIfPresent("extraLLVMCMakeOptions", default: extraLLVMCMakeOptions)
        extraSwiftArgs = try container.decodeIfPresent("extraSwiftArgs", default: extraSwiftArgs)
        useCustomBuildScriptArguments = try container.decodeIfPresent("useCustomBuildScriptArguments", default: useCustomBuildScriptArguments)
        customBuildScriptArguments = try container.decodeIfPresent("customBuildScriptArguments", default: customBuildScriptArguments)
        extraArguments = try container.decodeIfPresent("extraArguments", default: extraArguments)
    }

    public mutating func applyPreset(_ name: String) {
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

nonisolated private struct BuildOptionsCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }

    public static func key(_ value: String) -> Self {
        Self(stringValue: value)!
    }
}

nonisolated private extension KeyedDecodingContainer where Key == BuildOptionsCodingKey {
    func decodeIfPresent<T: Decodable>(_ key: String, default defaultValue: T) throws -> T {
        try decodeIfPresent(T.self, forKey: .key(key)) ?? defaultValue
    }
}
