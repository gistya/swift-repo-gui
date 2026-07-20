import Foundation

nonisolated public enum BuildCommandBuilder {
    public static func command(
        kind: BuildOperationKind,
        project: SwiftProjectInfo,
        buildSubdir: String,
        options: BuildOptions,
        targetRepository: String = "",
        changedRepositories: [SwiftRepository] = [],
        matchTimestamp: Bool = false
    ) -> (executable: String, arguments: [String], display: String, workingDirectory: URL) {
        switch kind {
        case .incrementalFrontend:
            return ninjaCommand(
                project: project,
                buildSubdir: buildSubdir,
                target: "bin/swift-frontend",
                repoName: "swift"
            )
        case .incrementalSwiftRepo:
            return ninjaCommand(
                project: project,
                buildSubdir: buildSubdir,
                target: nil,
                repoName: "swift"
            )
        case .incrementalEverything:
            return ninjaCommand(
                project: project,
                buildSubdir: buildSubdir,
                target: nil,
                repoName: nil
            )
        case .buildScript, .freshBuild:
            return buildScriptCommand(
                project: project,
                options: options,
                clean: kind == .freshBuild
            )
        case .updateDependencies:
            return updateCheckoutCommand(project: project, matchTimestamp: matchTimestamp)
        case .updateAndRebuild:
            if changedRepositories.isEmpty {
                return ninjaCommand(
                    project: project,
                    buildSubdir: buildSubdir,
                    target: "bin/swift-frontend",
                    repoName: "swift"
                )
            }
            return chainedCommands(
                project: project,
                buildSubdir: buildSubdir,
                repositories: changedRepositories
            )
        case .dependencyBuild:
            let repo = targetRepository.isEmpty ? "swift" : targetRepository
            return ninjaCommand(
                project: project,
                buildSubdir: buildSubdir,
                target: nil,
                repoName: repo
            )
        case .buildToolchain:
            // Toolchain builds carry a `ToolchainRecipeDraft` (not `BuildOptions`); AppSession
            // assembles the full command and injects it via `.start(job)`, so this path is unused.
            return (
                executable: project.swiftDirectory.appendingPathComponent("utils/build-toolchain").path,
                arguments: [],
                display: "build-toolchain",
                workingDirectory: project.swiftDirectory
            )
        }
    }

    private static func ninjaCommand(
        project: SwiftProjectInfo,
        buildSubdir: String,
        target: String?,
        repoName: String?
    ) -> (executable: String, arguments: [String], display: String, workingDirectory: URL) {
        let platform = ProjectService.platformName
        let arch = ProjectService.machineArch
        let ninjaBuildRoot: URL
        if let repoName {
            let dirName = ProjectService.repoNinjaDirectoryName(repoName, platform: platform, arch: arch)
            ninjaBuildRoot = project.buildRoot.appendingPathComponent(buildSubdir, isDirectory: true).appendingPathComponent(dirName, isDirectory: true)
        } else {
            ninjaBuildRoot = project.buildRoot
                .appendingPathComponent(buildSubdir, isDirectory: true)
                .appendingPathComponent(project.swiftBuildDirectoryName, isDirectory: true)
        }

        var args = ["-C", ninjaBuildRoot.path]
        if let target { args.append(target) }

        let ninja = resolveNinja(in: project)
        let display = ([ninja.displayName] + args).map(shellQuote).joined(separator: " ")
        return (ninja.executable, ninja.argumentPrefix + args, display, project.root)
    }

    private static func chainedCommands(
        project: SwiftProjectInfo,
        buildSubdir: String,
        repositories: [SwiftRepository]
    ) -> (executable: String, arguments: [String], display: String, workingDirectory: URL) {
        let platform = ProjectService.platformName
        let arch = ProjectService.machineArch
        let lines = repositories.map { repo -> String in
            let dirName = ProjectService.repoNinjaDirectoryName(repo.name, platform: platform, arch: arch)
            let path = project.buildRoot.appendingPathComponent(buildSubdir).appendingPathComponent(dirName).path
            let ninja = resolveNinja(in: project).shellToken
            if repo.name == "swift" {
                return "\(ninja) -C \(shellQuote(path)) bin/swift-frontend"
            }
            return "\(ninja) -C \(shellQuote(path))"
        }
        let script = lines.joined(separator: " && ")
        return ("/bin/zsh", ["-lc", script], script, project.root)
    }

    public static func buildScriptCommand(
        project: SwiftProjectInfo,
        options: BuildOptions,
        clean: Bool = false
    ) -> (executable: String, arguments: [String], display: String, workingDirectory: URL) {
        var args: [String] = []

        if options.useCustomBuildScriptArguments {
            args.append(contentsOf: buildScriptArguments(from: options.customBuildScriptArguments))
        } else if !options.preset.isEmpty {
            args.append("--preset=\(options.preset)")
        } else {
            if clean || options.clean { args.append("-c") }
            if options.release { args.append("-R") }
            if options.releaseDebugInfo && !options.release { args.append("-r") }
            if options.debug { args.append("-d") }
            if options.minSizeRelease { args.append("--min-size-release") }
            if options.reconfigure { args.append("--reconfigure") }
            if options.assertions { args.append("-a") }
            if options.noAssertions { args.append("-A") }
            if options.debugSwift { args.append("--debug-swift") }
            if options.debugSwiftStdlib { args.append("--debug-swift-stdlib") }
            if options.debugLLVM { args.append("--debug-llvm") }
            if options.skipBuildOSXStdlib { args.append("--skip-build-osx") }
            if options.skipBuildIOS { args.append("--skip-ios") }
            if options.skipBuildBenchmarks { args.append("--skip-build-benchmarks") }
            if options.test { args.append("-t") }
            if options.validationTests { args.append("-T") }
            if options.sccache { args.append("--sccache") }
            if options.distcc { args.append("--distcc") }
            if options.enableCaching { args.append("--enable-caching") }
            if options.ltoThin { args.append("--lto=thin") }
            else if options.lto { args.append("--lto") }
            if options.enableASAN { args.append("--enable-asan") }
            if options.enableUBSAN { args.append("--enable-ubsan") }
            if options.enableTSAN { args.append("--enable-tsan") }
            if options.verboseBuild { args.append("--verbose-build") }
            if options.dryRun { args.append("-n") }
            if options.buildNinja { args.append("--build-ninja") }
            if options.useMake { args.append("-m") }
            if options.installablePackage {
                let custom = options.installablePackagePath.trimmingCharacters(in: .whitespacesAndNewlines)
                let packageURL: URL
                if custom.isEmpty {
                    packageURL = ((try? AppPaths.exportsDirectory()) ?? project.buildRoot)
                        .appendingPathComponent("swift-installable-package.tar.gz")
                } else {
                    packageURL = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
                }
                args.append(contentsOf: ["--installable-package", packageURL.path])
            }
            if options.swiftPM { args.append("-p") }
            if options.llbuild { args.append("-b") }
            if options.lldb { args.append("-l") }
            if options.foundation { args.append("--foundation") }
            if options.libDispatch { args.append("--libdispatch") }
            if options.xctest { args.append("--xctest") }
            if options.swiftDriver { args.append("--swift-driver") }
            if options.swiftTesting { args.append("--swift-testing") }
            if options.swiftTestingMacros { args.append("--swift-testing-macros") }
            if options.swiftSyntax { args.append("--swiftsyntax") }
            if options.sourceKitLSP { args.append("--sourcekit-lsp") }
            if options.indexStoreDB { args.append("--indexstore-db") }
            if options.installAll { args.append("--install-all") }
            if options.installSwift { args.append("--install-swift") }
            if options.installLLVM { args.append("--install-llvm") }
            if options.installSwiftPM { args.append("--install-swiftpm") }
            if options.installLLDB { args.append("--install-lldb") }
            if options.installSwiftDriver { args.append("--install-swift-driver") }
            if options.installSwiftTesting { args.append("--install-swift-testing") }
            if options.installSwiftTestingMacros { args.append("--install-swift-testing-macros") }
            if options.installSwiftSyntax { args.append("--install-swiftsyntax") }
            if options.installSourceKitLSP { args.append("--install-sourcekit-lsp") }
            if options.swiftDisableDeadStripping { args.append("--swift-disable-dead-stripping") }
            if options.buildSwiftDynamicStdlib { args.append("--build-swift-dynamic-stdlib=1") }
            if options.buildSwiftDynamicSDKOverlay { args.append("--build-swift-dynamic-sdk-overlay=1") }
            if options.buildSwiftStaticStdlib { args.append("--build-swift-static-stdlib=1") }
            if options.buildSwiftStaticSDKOverlay { args.append("--build-swift-static-sdk-overlay=1") }
            if !options.buildSubdir.isEmpty { args.append("--build-subdir=\(options.buildSubdir)") }
            appendValueArgument("--host-target", options.hostTarget, to: &args)
            appendValueArgument("--stdlib-deployment-targets", options.stdlibDeploymentTargets, to: &args)
            appendValueArgument("--build-stdlib-deployment-targets", options.buildStdlibDeploymentTargets, to: &args)
            appendValueArgument("--install-prefix", options.installPrefix, to: &args)
            appendValueArgument("--install-destdir", options.installDestdir, to: &args)
            appendValueArgument("--install-symroot", options.installSymroot, to: &args)
            appendValueArgument("--darwin-xcrun-toolchain", options.darwinXCRunToolchain, to: &args)
            appendValueArgument("--cmake", options.cmake, to: &args)
            appendValueArgument("--host-cc", options.hostCC, to: &args)
            appendValueArgument("--host-cxx", options.hostCXX, to: &args)
            appendValueArgument("--llvm-targets-to-build", options.llvmTargetsToBuild, to: &args)
            appendValueArgument("--build-args", options.buildArgs, to: &args)
            appendValueArgument("--lit-args", options.litArgs, to: &args)
            appendValueArgument("--extra-cmake-options", options.extraCMakeOptions, to: &args)
            appendValueArgument("--extra-swift-cmake-options", options.extraSwiftCMakeOptions, to: &args)
            appendValueArgument("--llvm-cmake-options", options.llvmCMakeOptions, to: &args)
            appendValueArgument("--extra-llvm-cmake-options", options.extraLLVMCMakeOptions, to: &args)
            appendValueArgument("--extra-swift-args", options.extraSwiftArgs, to: &args)
            if options.jobs > 0 { args.append("-j\(options.jobs)") }
            if options.litJobs > 0 { args.append("--lit-jobs=\(options.litJobs)") }

            let archs = options.swiftDarwinSupportedArchs.isEmpty ? ProjectService.machineArch : options.swiftDarwinSupportedArchs
            #if os(macOS)
            args.append("--swift-darwin-supported-archs")
            args.append(archs)
            #endif
        }

        if !options.useCustomBuildScriptArguments {
            args.append(contentsOf: buildScriptArguments(from: options.extraArguments))
        }

        let script = project.buildScript.path
        let display = ([script] + args).map(shellQuote).joined(separator: " ")
        return (script, args, display, project.swiftDirectory)
    }

    public static func updateCheckoutCommand(
        project: SwiftProjectInfo,
        matchTimestamp: Bool
    ) -> (executable: String, arguments: [String], display: String, workingDirectory: URL) {
        // Never let update-checkout touch the swift repo: the user is on their own branch, and moving it
        // to a scheme's branch would discard that checkout. Skipping it keeps the current branch checked
        // out and updates only the sibling repos to the versions it needs.
        var args = ["--source-root", project.root.path, "--skip-repository", "swift"]
        // Pin a --scheme ONLY when the user explicitly chose one in the Checkout scheme menu. In Auto
        // mode we pass none, so update-checkout uses its own default scheme for the siblings; with
        // --match-timestamp each one lands at the commit matching the swift branch's HEAD date. Passing a
        // non-scheme branch name here is exactly what broke it before ("'NoneType' object is not iterable").
        if project.schemeResolutionSource == .manualOverride, !project.checkoutScheme.isEmpty {
            args.append(contentsOf: ["--scheme", project.checkoutScheme])
        }
        if matchTimestamp { args.append("--match-timestamp") }
        let script = project.updateCheckout.path
        let display = "cd \(shellQuote(project.swiftDirectory.path)) && \(shellQuote(script)) \(args.map(shellQuote).joined(separator: " "))"
        return (script, args, display, project.swiftDirectory)
    }

    public static func freshNinjaClean(
        project: SwiftProjectInfo,
        buildSubdir: String,
        repoName: String?
    ) -> (executable: String, arguments: [String], display: String, workingDirectory: URL) {
        let platform = ProjectService.platformName
        let arch = ProjectService.machineArch
        let dirName: String
        if let repoName {
            dirName = ProjectService.repoNinjaDirectoryName(repoName, platform: platform, arch: arch)
        } else {
            dirName = project.swiftBuildDirectoryName
        }
        let path = project.buildRoot.appendingPathComponent(buildSubdir).appendingPathComponent(dirName).path
        let ninja = resolveNinja(in: project)
        let display = "\(ninja.displayName) -C \(shellQuote(path)) -t clean && \(ninja.displayName) -C \(shellQuote(path))"
        let script = "\(ninja.shellToken) -C \(shellQuote(path)) -t clean && \(ninja.shellToken) -C \(shellQuote(path))"
        return ("/bin/zsh", ["-lc", script], display, project.root)
    }

    public static func findNinja(in project: SwiftProjectInfo) -> String? {
        let candidates = [
            project.root.appendingPathComponent("ninja/ninja"),
            project.buildRoot.appendingPathComponent("ninja-macosx-arm64/bin/ninja"),
            project.buildRoot.appendingPathComponent("ninja-macosx-x86_64/bin/ninja"),
        ] + pathCandidates(named: "ninja")
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate.path
        }
        return nil
    }

    private static func resolveNinja(in project: SwiftProjectInfo) -> NinjaExecutable {
        if let path = findNinja(in: project) {
            return NinjaExecutable(
                executable: path,
                argumentPrefix: [],
                displayName: path,
                shellToken: shellQuote(path)
            )
        }

        return NinjaExecutable(
            executable: "/usr/bin/env",
            argumentPrefix: ["ninja"],
            displayName: "ninja",
            shellToken: "ninja"
        )
    }

    private static func pathCandidates(named executableName: String) -> [URL] {
        let pathDirectories = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let commonDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]

        var seen: Set<String> = []
        return (pathDirectories + commonDirectories).compactMap { directory in
            guard !directory.isEmpty, seen.insert(directory).inserted else { return nil }
            return URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(executableName)
        }
    }

    public static func shellQuote(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }
        if value.contains(" ") || value.contains("'") {
            return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return value
    }

    private static func appendValueArgument(_ flag: String, _ value: String, to args: inout [String]) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        args.append("\(flag)=\(trimmed)")
    }

    public static func buildScriptArguments(from text: String) -> [String] {
        let tokens = shellSplit(text)
        guard let scriptIndex = tokens.lastIndex(where: isBuildScriptToken) else {
            return tokens.filter { !shellCommandSeparators.contains($0) }
        }
        return tokens[tokens.index(after: scriptIndex)...]
            .filter { !shellCommandSeparators.contains($0) }
    }

    private static let shellCommandSeparators: Set<String> = ["&&", ";"]

    private static func isBuildScriptToken(_ token: String) -> Bool {
        let normalized = token.replacingOccurrences(of: "\\", with: "/")
        return normalized == "build-script"
            || normalized.hasSuffix("/build-script")
            || normalized.hasSuffix("/swift/utils/build-script")
            || normalized.hasSuffix("/utils/build-script")
    }

    private static func shellSplit(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var iterator = Array(text).makeIterator()
        var quote: Character?

        while let character = iterator.next() {
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                    continue
                }
                if activeQuote == "\"", character == "\\", let next = iterator.next() {
                    if next.isNewline {
                        continue
                    }
                    current.append(next)
                    continue
                }
                current.append(character)
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
                continue
            }

            if character == "\\" {
                guard let next = iterator.next() else {
                    current.append(character)
                    continue
                }
                if next.isNewline {
                    continue
                }
                current.append(next)
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            if character == "#", current.isEmpty {
                while let next = iterator.next(), !next.isNewline {}
                continue
            }

            current.append(character)
        }

        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}

private struct NinjaExecutable {
    public let executable: String
    public let argumentPrefix: [String]
    public let displayName: String
    public let shellToken: String
}
