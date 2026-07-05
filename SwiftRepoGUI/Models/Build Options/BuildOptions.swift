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
    var swiftTestingMacros = false
    var swiftSyntax = false
    var sourceKitLSP = false
    var indexStoreDB = false
    var foundation = false
    var libDispatch = false
    var xctest = false
    var installablePackage = false
    var installAll = false
    var installSwift = false
    var installLLVM = false
    var installSwiftPM = false
    var installLLDB = false
    var installSwiftDriver = false
    var installSwiftTesting = false
    var installSwiftTestingMacros = false
    var installSwiftSyntax = false
    var installSourceKitLSP = false
    var swiftDarwinSupportedArchs = ""
    var hostTarget = ""
    var stdlibDeploymentTargets = ""
    var buildStdlibDeploymentTargets = ""
    var swiftDisableDeadStripping = true
    var buildSwiftDynamicStdlib = false
    var buildSwiftDynamicSDKOverlay = false
    var buildSwiftStaticStdlib = false
    var buildSwiftStaticSDKOverlay = false
    var buildSubdir = ""
    var preset = ""
    var installPrefix = ""
    var installDestdir = ""
    var installSymroot = ""
    var darwinXCRunToolchain = ""
    var cmake = ""
    var hostCC = ""
    var hostCXX = ""
    var llvmTargetsToBuild = ""
    var buildArgs = ""
    var litArgs = ""
    var extraCMakeOptions = ""
    var extraSwiftCMakeOptions = ""
    var llvmCMakeOptions = ""
    var extraLLVMCMakeOptions = ""
    var extraSwiftArgs = ""
    var useCustomBuildScriptArguments = false
    var customBuildScriptArguments = ""
    var extraArguments = ""

    static let `default` = BuildOptions()

    init() {}

    init(from decoder: any Decoder) throws {
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

nonisolated private struct BuildOptionsCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }

    static func key(_ value: String) -> Self {
        Self(stringValue: value)!
    }
}

nonisolated private extension KeyedDecodingContainer where Key == BuildOptionsCodingKey {
    func decodeIfPresent<T: Decodable>(_ key: String, default defaultValue: T) throws -> T {
        try decodeIfPresent(T.self, forKey: .key(key)) ?? defaultValue
    }
}
