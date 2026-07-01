import CompositionalInit
import Foundation
import SwiftXState

nonisolated enum BuildSettingsState: String, StateIdentifying {
    case ready
    static var _blank: BuildSettingsState { .ready }
}

nonisolated enum BuildSettingsEvent: EventIdentifying {
    case setOptions(BuildOptions)
    case setRepository(String)
    case setBoolOption(key: String, value: Bool)
    case setIntOption(key: String, value: Int)
    case setStringOption(key: String, value: String)
    case applyPreset(String)
    case restore(BuildOptions, String)
    static var _blank: BuildSettingsEvent { .setOptions(.default) }
}

nonisolated struct BuildSettingsContext: Sendable, Equatable {
    var options: BuildOptions = .default
    var selectedRepository: String = "swift"
}

struct BuildSettingsMachine: StateMachine {
    typealias Context = BuildSettingsContext
    typealias StateID = BuildSettingsState
    typealias EventID = BuildSettingsEvent

    var context: BuildSettingsContext { .init() }

    var machine: some XStateMachine {
        XState(.ready) {
            XTransition(on: BuildSettingsEvent.setOptions, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .setOptions(options)? = args.event { ctx.options = options }
                return ctx
            }
            XTransition(on: BuildSettingsEvent.setRepository, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .setRepository(repo)? = args.event { ctx.selectedRepository = repo }
                return ctx
            }
            XTransition(on: BuildSettingsEvent.setBoolOption, to: .ready).action { args, _ in
                guard case let .setBoolOption(key, value)? = args.event else { return args.context }
                return args.context.updatingBool(key: key, value: value)
            }
            XTransition(on: BuildSettingsEvent.setIntOption, to: .ready).action { args, _ in
                guard case let .setIntOption(key, value)? = args.event else { return args.context }
                return args.context.updatingInt(key: key, value: value)
            }
            XTransition(on: BuildSettingsEvent.setStringOption, to: .ready).action { args, _ in
                guard case let .setStringOption(key, value)? = args.event else { return args.context }
                return args.context.updatingString(key: key, value: value)
            }
            XTransition(on: BuildSettingsEvent.applyPreset, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .applyPreset(name)? = args.event {
                    ctx.options.applyPreset(name)
                }
                return ctx
            }
            XTransition(on: BuildSettingsEvent.restore, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .restore(options, repo)? = args.event {
                    ctx.options = options
                    ctx.selectedRepository = repo.isEmpty ? "swift" : repo
                }
                return ctx
            }
        }
        .initial()
    }
}

private extension BuildSettingsContext {
    nonisolated func updatingBool(key: String, value: Bool) -> Self {
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

    nonisolated func updatingInt(key: String, value: Int) -> Self {
        var copy = self
        if key == "jobs" { copy.options.jobs = value }
        if key == "litJobs" { copy.options.litJobs = value }
        return copy
    }

    nonisolated func updatingString(key: String, value: String) -> Self {
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
