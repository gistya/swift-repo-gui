import Foundation

enum BuildCommandBuilder {
    static func command(
        kind: BuildOperationKind,
        project: SwiftProjectInfo,
        buildSubdir: String,
        options: BuildOptions,
        targetRepository: String = "",
        changedRepositories: [SwiftRepository] = []
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
            return updateCheckoutCommand(project: project, scheme: project.checkoutScheme, matchTimestamp: true)
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
            ninjaBuildRoot = project.buildRoot.appendingPathComponent(buildSubdir, isDirectory: true)
        }

        var args = ["-C", ninjaBuildRoot.path]
        if let target { args.append(target) }

        let ninjaPath = findNinja(in: project) ?? "ninja"
        let display = ([ninjaPath] + args).joined(separator: " ")
        return (ninjaPath, args, display, project.root)
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
            if repo.name == "swift" {
                return "ninja -C '\(path)' bin/swift-frontend"
            }
            return "ninja -C '\(path)'"
        }
        let script = lines.joined(separator: " && ")
        return ("/bin/zsh", ["-lc", script], script, project.root)
    }

    static func buildScriptCommand(
        project: SwiftProjectInfo,
        options: BuildOptions,
        clean: Bool = false
    ) -> (executable: String, arguments: [String], display: String, workingDirectory: URL) {
        var args: [String] = []

        if !options.preset.isEmpty {
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
            if options.swiftPM { args.append("-p") }
            if options.llbuild { args.append("-b") }
            if options.lldb { args.append("-l") }
            if options.swiftDriver { args.append("--swift-driver") }
            if options.swiftTesting { args.append("--swift-testing") }
            if options.installSwift { args.append("--install-swift") }
            if options.installLLVM { args.append("--install-llvm") }
            if options.installSwiftPM { args.append("--install-swiftpm") }
            if options.swiftDisableDeadStripping { args.append("--swift-disable-dead-stripping") }
            if !options.buildSubdir.isEmpty { args.append("--build-subdir=\(options.buildSubdir)") }
            if options.jobs > 0 { args.append("-j\(options.jobs)") }
            if options.litJobs > 0 { args.append("--lit-jobs=\(options.litJobs)") }

            let archs = options.swiftDarwinSupportedArchs.isEmpty ? ProjectService.machineArch : options.swiftDarwinSupportedArchs
            #if os(macOS)
            args.append("--swift-darwin-supported-archs")
            args.append(archs)
            #endif

            for line in options.extraArguments.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { args.append(trimmed) }
            }
        }

        let script = project.buildScript.path
        let display = ([script] + args).map(shellQuote).joined(separator: " ")
        return (script, args, display, project.swiftDirectory)
    }

    static func updateCheckoutCommand(
        project: SwiftProjectInfo,
        scheme: String,
        matchTimestamp: Bool
    ) -> (executable: String, arguments: [String], display: String, workingDirectory: URL) {
        var args = ["--source-root", project.root.path, "--scheme", scheme]
        if matchTimestamp { args.append("--match-timestamp") }
        let script = project.updateCheckout.path
        let display = "cd \(shellQuote(project.swiftDirectory.path)) && \(shellQuote(script)) \(args.map(shellQuote).joined(separator: " "))"
        return (script, args, display, project.swiftDirectory)
    }

    static func freshNinjaClean(
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
            dirName = "swift-\(platform)-\(arch)"
        }
        let path = project.buildRoot.appendingPathComponent(buildSubdir).appendingPathComponent(dirName).path
        let ninjaPath = findNinja(in: project) ?? "ninja"
        let args = ["-C", path, "-t", "clean"]
        let display = "\(ninjaPath) -C '\(path)' -t clean && \(ninjaPath) -C '\(path)'"
        let script = "\(shellQuote(ninjaPath)) -C \(shellQuote(path)) -t clean && \(shellQuote(ninjaPath)) -C \(shellQuote(path))"
        return ("/bin/zsh", ["-lc", script], display, project.root)
    }

    static func findNinja(in project: SwiftProjectInfo) -> String? {
        let candidates = [
            project.root.appendingPathComponent("ninja/ninja"),
            project.buildRoot.appendingPathComponent("ninja-macosx-arm64/bin/ninja"),
            project.buildRoot.appendingPathComponent("ninja-macosx-x86_64/bin/ninja"),
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate.path
        }
        return nil
    }

    static func shellQuote(_ value: String) -> String {
        if value.contains(" ") || value.contains("'") {
            return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return value
    }
}