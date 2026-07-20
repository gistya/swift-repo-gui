import SwiftXState

nonisolated public struct BuildSettingsContext: Sendable, Equatable {
    public var options: BuildOptions = .default
    public var selectedRepository: String = "swift"

    nonisolated public func updatingBool(key: String, value: Bool) -> Self {
        var copy = self
        switch key {
        case "release": copy.options.release = value
        case "releaseDebugInfo": copy.options.releaseDebugInfo = value
        case "debug": copy.options.debug = value
        case "clean": copy.options.clean = value
        case "reconfigure": copy.options.reconfigure = value
        case "assertions": copy.options.assertions = value
        case "noAssertions": copy.options.noAssertions = value
        case "debugSwift": copy.options.debugSwift = value
        case "debugSwiftStdlib": copy.options.debugSwiftStdlib = value
        case "debugLLVM": copy.options.debugLLVM = value
        case "skipBuildOSXStdlib": copy.options.skipBuildOSXStdlib = value
        case "skipBuildIOS": copy.options.skipBuildIOS = value
        case "skipBuildBenchmarks": copy.options.skipBuildBenchmarks = value
        case "sccache": copy.options.sccache = value
        case "distcc": copy.options.distcc = value
        case "enableCaching": copy.options.enableCaching = value
        case "lto": copy.options.lto = value
        case "ltoThin": copy.options.ltoThin = value
        case "enableASAN": copy.options.enableASAN = value
        case "enableUBSAN": copy.options.enableUBSAN = value
        case "enableTSAN": copy.options.enableTSAN = value
        case "test": copy.options.test = value
        case "validationTests": copy.options.validationTests = value
        case "swiftPM": copy.options.swiftPM = value
        case "llbuild": copy.options.llbuild = value
        case "lldb": copy.options.lldb = value
        case "swiftDriver": copy.options.swiftDriver = value
        case "swiftTesting": copy.options.swiftTesting = value
        case "swiftTestingMacros": copy.options.swiftTestingMacros = value
        case "swiftSyntax": copy.options.swiftSyntax = value
        case "sourceKitLSP": copy.options.sourceKitLSP = value
        case "indexStoreDB": copy.options.indexStoreDB = value
        case "foundation": copy.options.foundation = value
        case "libDispatch": copy.options.libDispatch = value
        case "xctest": copy.options.xctest = value
        case "installablePackage": copy.options.installablePackage = value
        case "installAll": copy.options.installAll = value
        case "installSwift": copy.options.installSwift = value
        case "installLLVM": copy.options.installLLVM = value
        case "installSwiftPM": copy.options.installSwiftPM = value
        case "installLLDB": copy.options.installLLDB = value
        case "installSwiftDriver": copy.options.installSwiftDriver = value
        case "installSwiftTesting": copy.options.installSwiftTesting = value
        case "installSwiftTestingMacros": copy.options.installSwiftTestingMacros = value
        case "installSwiftSyntax": copy.options.installSwiftSyntax = value
        case "installSourceKitLSP": copy.options.installSourceKitLSP = value
        case "swiftDisableDeadStripping": copy.options.swiftDisableDeadStripping = value
        case "buildSwiftDynamicStdlib": copy.options.buildSwiftDynamicStdlib = value
        case "buildSwiftDynamicSDKOverlay": copy.options.buildSwiftDynamicSDKOverlay = value
        case "buildSwiftStaticStdlib": copy.options.buildSwiftStaticStdlib = value
        case "buildSwiftStaticSDKOverlay": copy.options.buildSwiftStaticSDKOverlay = value
        case "useCustomBuildScriptArguments": copy.options.useCustomBuildScriptArguments = value
        case "verboseBuild": copy.options.verboseBuild = value
        case "dryRun": copy.options.dryRun = value
        case "buildNinja": copy.options.buildNinja = value
        case "useMake": copy.options.useMake = value
        default: break
        }
        return copy
    }

    nonisolated public func updatingInt(key: String, value: Int) -> Self {
        var copy = self
        if key == "jobs" { copy.options.jobs = value }
        if key == "litJobs" { copy.options.litJobs = value }
        return copy
    }

    nonisolated public func updatingString(key: String, value: String) -> Self {
        var copy = self
        switch key {
        case "preset": copy.options.preset = value
        case "buildSubdir": copy.options.buildSubdir = value
        case "extraArguments": copy.options.extraArguments = value
        case "customBuildScriptArguments": copy.options.customBuildScriptArguments = value
        case "swiftDarwinSupportedArchs": copy.options.swiftDarwinSupportedArchs = value
        case "hostTarget": copy.options.hostTarget = value
        case "stdlibDeploymentTargets": copy.options.stdlibDeploymentTargets = value
        case "buildStdlibDeploymentTargets": copy.options.buildStdlibDeploymentTargets = value
        case "installablePackagePath": copy.options.installablePackagePath = value
        case "installPrefix": copy.options.installPrefix = value
        case "installDestdir": copy.options.installDestdir = value
        case "installSymroot": copy.options.installSymroot = value
        case "darwinXCRunToolchain": copy.options.darwinXCRunToolchain = value
        case "cmake": copy.options.cmake = value
        case "hostCC": copy.options.hostCC = value
        case "hostCXX": copy.options.hostCXX = value
        case "llvmTargetsToBuild": copy.options.llvmTargetsToBuild = value
        case "buildArgs": copy.options.buildArgs = value
        case "litArgs": copy.options.litArgs = value
        case "extraCMakeOptions": copy.options.extraCMakeOptions = value
        case "extraSwiftCMakeOptions": copy.options.extraSwiftCMakeOptions = value
        case "llvmCMakeOptions": copy.options.llvmCMakeOptions = value
        case "extraLLVMCMakeOptions": copy.options.extraLLVMCMakeOptions = value
        case "extraSwiftArgs": copy.options.extraSwiftArgs = value
        default: break
        }
        return copy
    }
}
