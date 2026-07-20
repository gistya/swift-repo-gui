import Testing
import Foundation
import SwiftXState
@testable import SwiftBuild

@Suite(.serialized)
struct SwiftRepoCoreTests {

    @Test func progressParserExtractsNinjaCounters() async throws {
        let progress = ProgressParser.parse(
            line: "[42/100] Building Swift source",
            startedAt: Date().addingTimeInterval(-10),
            previous: .zero
        )

        #expect(progress.completedSteps == 42)
        #expect(progress.totalSteps == 100)
        #expect(progress.fraction == 0.42)
        #expect(progress.message == "[42/100] Building Swift source")
    }

    @Test func progressParserKeepsActivityMessageWithoutCounters() async throws {
        let progress = ProgressParser.parse(
            line: "Updating checkout for llvm-project",
            startedAt: Date(),
            previous: .zero
        )

        #expect(progress.completedSteps == 0)
        #expect(progress.totalSteps == 0)
        #expect(progress.fraction == 0)
        #expect(progress.message == "Updating checkout for llvm-project")
    }

    @Test func progressParserClearsCompletedNinjaPhaseForCMakeActivity() async throws {
        let completedPhase = BuildProgressSnapshot(
            completedSteps: 42,
            totalSteps: 42,
            fraction: 1,
            etaSeconds: nil,
            message: "[42/42] Re-running CMake"
        )

        let progress = ProgressParser.parse(
            line: "-- Performing Test CMAKE_HAVE_LIBC_PTHREAD",
            startedAt: Date(),
            previous: completedPhase
        )

        #expect(progress.completedSteps == 0)
        #expect(progress.totalSteps == 0)
        #expect(progress.fraction == 0)
        #expect(progress.message == "-- Performing Test CMAKE_HAVE_LIBC_PTHREAD")
    }

    @Test func buildStageIgnoresTestWordInCompilerOutput() throws {
        // A ninja compile line that merely mentions "test" is NOT the testing phase. The stage is
        // whatever the last authoritative banner set (here: the base `.building`), never a substring.
        var context = BuildOperationsContext()
        context.activeJob = makeBuildJob(kind: .buildScript, displayCommand: "./swift/utils/build-script --test")
        context.progress = BuildProgressSnapshot(
            completedSteps: 3,
            totalSteps: 20,
            fraction: 0.15,
            etaSeconds: nil,
            message: "[3/20] Building CXX object .../SwiftParseTests.cpp.o",
            stage: .building
        )

        #expect(BuildStage.stage(for: context) == .building)
    }

    @Test func buildStageTracksLineTypeAndRealBanners() throws {
        // Building/testing follow what the output is actually doing: a `[n/m]` counter is compiling, a
        // lit PASS/FAIL is a running test. Install/build banners move it further. The one-time
        // plan-summary lines build-script prints at startup are ignored.
        #expect(BuildStage.detect(bannerIn: "[1502/5533] /usr/bin/clang++ -c SomeTestFile.cpp") == .building)
        #expect(BuildStage.detect(bannerIn: "[42/100] Linking install_name_tool target") == .building)
        #expect(BuildStage.detect(bannerIn: "PASS: Swift(macosx-arm64) :: Parse/x.swift (1 of 9)") == .testing)
        #expect(BuildStage.detect(bannerIn: "FAIL: Swift(macosx-arm64) :: crash/y.swift") == .testing)

        #expect(BuildStage.detect(bannerIn: "--- Building swift ---") == .building)
        #expect(BuildStage.detect(bannerIn: "--- Cleaning swift ---") == .building)
        #expect(BuildStage.detect(bannerIn: "--- Building tests for swift ---") == .building)
        #expect(BuildStage.detect(bannerIn: "--- Finished tests for swift ---") == .building)
        #expect(BuildStage.detect(bannerIn: "--- Installing swift ---") == .deploying)
        #expect(BuildStage.detect(bannerIn: "--- Extracting symbols ---") == .deploying)
        #expect(BuildStage.detect(bannerIn: "--- Creating installable package ---") == .deploying)

        // Plan-summary lines and test-phase banners do NOT move the stage — Testing comes from PASS/FAIL,
        // so build-script's startup plan ("Running Swift tests for: …") can no longer stick on Testing.
        #expect(BuildStage.detect(bannerIn: "Running Swift tests for: check-swift-validation-macosx-arm64") == nil)
        #expect(BuildStage.detect(bannerIn: "Building the standard library for: swift-stdlib-macosx-arm64") == nil)
        #expect(BuildStage.detect(bannerIn: "Running Swift benchmarks for: macosx-arm64") == nil)
        #expect(BuildStage.detect(bannerIn: "--- Running tests for swift ---") == nil)
        #expect(BuildStage.detect(bannerIn: "--- Running LLDB unit tests ---") == nil)
        #expect(BuildStage.detect(bannerIn: "--- check-swift ---") == nil)
        #expect(BuildStage.detect(bannerIn: "--- Bootstrap Local CMake ---") == nil)
        #expect(BuildStage.detect(bannerIn: "--- Can't execute tests for host, skipping... ---") == nil)
    }

    @Test func progressParserDrivesStageFromLineType() throws {
        let started = Date()
        // A compile-progress line resets the stage to building — even if a stale plan line had left it
        // on testing (the reported "LED says Testing while [n/m] compiling" bug).
        let building = ProgressParser.parse(
            line: "[3548/7278][ 48%] clang -DGTEST_HAS_RTTI=0 -c magic-symbols.c",
            startedAt: started,
            previous: BuildProgressSnapshot(completedSteps: 0, totalSteps: 0, fraction: 0, etaSeconds: nil, message: nil, stage: .testing)
        )
        #expect(building.stage == .building)

        // A lit result advances to testing.
        let testing = ProgressParser.parse(
            line: "PASS: Swift(macosx-arm64) :: Parse/some_test.swift (123 of 456)",
            startedAt: started,
            previous: building
        )
        #expect(testing.stage == .testing)

        // A real install banner advances to deploying.
        let deploying = ProgressParser.parse(
            line: "--- Installing swift ---",
            startedAt: started,
            previous: testing
        )
        #expect(deploying.stage == .deploying)
    }

    @Test func buildStageModuleLabelExtractsTargets() throws {
        // Verb-anchored: the target follows a known build verb.
        #expect(BuildStage.moduleLabel(for: "[3/20] Testing SwiftParseTests") == "SwiftParseTests")
        // Known-target path component wins over the object-file name.
        #expect(BuildStage.moduleLabel(for: "[191/800] Building CXX object projects/libcxx/src/CMakeFiles/cxx_shared.dir/algorithm.cpp.o") == "libcxx")
        // Phase banners name the product (or the phase, when there is no product).
        #expect(BuildStage.moduleLabel(for: "--- Installing swift ---") == "swift")
        #expect(BuildStage.moduleLabel(for: "--- Running tests for swift ---") == "swift")
        #expect(BuildStage.moduleLabel(for: "--- Extracting symbols ---") == "Extracting symbols")
        #expect(BuildStage.moduleLabel(for: "--- Creating installable package ---") == "Installable package")
    }

    @Test func buildStageModuleLabelRejectsJunkLines() throws {
        // The reported garbage: linker warnings, CMake install echoes, shell operators → no label.
        #expect(BuildStage.moduleLabel(for: "ld: warning: ignoring duplicate libraries: 'lib/libgtest.a', 'lib/libllvmSupport.a'") == nil)
        #expect(BuildStage.moduleLabel(for: "-- Installing: /Users/shad/dev/.../LLDB.framework/Headers") == nil)
        #expect(BuildStage.moduleLabel(for: "clang++ -o out && ninja -C build") == nil)
        #expect(BuildStage.moduleLabel(for: "--") == nil)
    }

    @Test func progressParserKeepsModuleLabelStickyOverJunk() throws {
        let started = Date()
        let good = ProgressParser.parse(
            line: "[3/20] Testing SwiftParseTests",
            startedAt: started,
            previous: .zero
        )
        #expect(good.moduleLabel == "SwiftParseTests")

        // A junk warning line must not clobber the last good target.
        let afterJunk = ProgressParser.parse(
            line: "ld: warning: ignoring duplicate libraries: 'lib/libgtest.a'",
            startedAt: started,
            previous: good
        )
        #expect(afterJunk.moduleLabel == "SwiftParseTests")
    }

    @Test func buildStageModuleDisplayUsesStickyLabel() throws {
        var context = BuildOperationsContext()
        context.activeJob = makeBuildJob(kind: .buildScript, displayCommand: "./swift/utils/build-script")
        context.progress = BuildProgressSnapshot(
            completedSteps: 3, totalSteps: 20, fraction: 0.15, etaSeconds: nil,
            message: "ld: warning: something noisy", stage: .deploying, moduleLabel: "libcxx"
        )
        #expect(BuildStage.moduleDisplay(for: context) == "libcxx")
    }

    @Test func buildStageClassifiesFailureFromIdleStatus() throws {
        var context = BuildOperationsContext()
        context.lastExitCode = 1
        context.statusMessage = "Build failed."

        #expect(BuildStage.stage(for: context) == .failed)
        #expect(BuildStage.moduleDisplay(for: context) == "ERROR")
    }

    @Test func trackerTrackDisplayDerivesArtistAndTitleFromFilename() throws {
        let track = TrackerModuleTrack(
            url: URL(fileURLWithPath: "/tmp/drozerix_-_bubble_machine.xm"),
            fileName: "drozerix_-_bubble_machine.xm",
            title: "drozerix_-_bubble_machine",
            format: "XM"
        )

        let display = track.nowPlaying(moduleTitle: nil)

        #expect(display.artist == "DROZERIX")
        #expect(display.title == "BUBBLE MACHINE")
        #expect(display.detail == "XM")
    }

    @Test func trackerTrackDisplayPrefersParsedModuleTitle() throws {
        let track = TrackerModuleTrack(
            url: URL(fileURLWithPath: "/tmp/drozerix_-_bubble_machine.xm"),
            fileName: "drozerix_-_bubble_machine.xm",
            title: "drozerix_-_bubble_machine",
            format: "XM"
        )

        let display = track.nowPlaying(moduleTitle: "Bubble Machine!")

        #expect(display.artist == "DROZERIX")
        #expect(display.title == "Bubble Machine!")
    }


    @Test func appSectionsNavigateLeftAndRightWithWraparound() throws {
        #expect(AppSectionID.build.next == .settings)
        #expect(AppSectionID.logs.next == .inspector)
        #expect(AppSectionID.inspector.next == .style)
        #expect(AppSectionID.style.next == .build)
        #expect(AppSectionID.build.previous == .style)
        #expect(AppSectionID.history.previous == .toolchain)
    }

    @Test func checkoutSchemeResolverUsesUnmatchedCurrentSwiftBranch() async throws {
        let swiftDirectory = try makeSwiftDirectory(
            branch: "feature/current-branch",
            checkoutConfig: """
            {
              "default-branch-scheme": "main",
              "branch-schemes": {
                "main": {
                  "aliases": ["swift/main", "main"],
                  "repos": { "swift": "main" }
                }
              }
            }
            """
        )

        let resolution = await CheckoutSchemeResolver.resolve(swiftDirectory: swiftDirectory)

        // A personal/fork branch is NOT a scheme. Passing its name as `--scheme` is what made
        // update-checkout fail with "'NoneType' object is not iterable", so we fall back to the
        // config's default scheme and only report the branch for display.
        #expect(resolution.scheme == "main")
        #expect(resolution.branch == "feature/current-branch")
        #expect(resolution.source == .defaultScheme)
        // The picker offers only real schemes — never the branch name, which would fail the same way.
        let schemes = await CheckoutSchemeResolver.availableSchemes(swiftDirectory: swiftDirectory)
        #expect(schemes.contains("main"))
        #expect(!schemes.contains("feature/current-branch"))
    }

    @Test func checkoutSchemeResolverUsesBranchPointingAtDetachedHead() async throws {
        let swiftDirectory = try makeSwiftDirectory(
            branch: "release/6.4.x",
            checkoutConfig: """
            {
              "default-branch-scheme": "main",
              "branch-schemes": {
                "main": {
                  "aliases": ["swift/main", "main", "stable/21.x"],
                  "repos": {
                    "swift": "main",
                    "llvm-project": "stable/21.x"
                  }
                },
                "release/6.4.x": {
                  "aliases": ["swift/release/6.4.x", "release/6.4.x"],
                  "repos": {
                    "swift": "release/6.4.x",
                    "llvm-project": "swift/release/6.4.x"
                  }
                }
              }
            }
            """
        )
        try runGit(["checkout", "--detach", "HEAD"], in: swiftDirectory)

        let resolution = await CheckoutSchemeResolver.resolve(swiftDirectory: swiftDirectory)

        #expect(resolution.scheme == "release/6.4.x")
        #expect(resolution.branch == "release/6.4.x")
        #expect(resolution.source == .branchName)
    }

    @Test func ninjaCommandUsesAbsoluteExecutable() throws {
        let project = makeProjectInfo()
        let command = BuildCommandBuilder.command(
            kind: .incrementalFrontend,
            project: project,
            buildSubdir: "debug",
            options: .default
        )

        #expect(command.executable.hasPrefix("/"))
        #expect(command.executable != "/ninja")
        #expect(command.executable != "ninja")
        if command.executable == "/usr/bin/env" {
            #expect(command.arguments.first == "ninja")
        }
        #expect(command.arguments.contains("bin/swift-frontend"))
    }

    @Test func incrementalEverythingUsesSwiftNinjaDirectory() throws {
        let project = makeProjectInfo()
        let command = BuildCommandBuilder.command(
            kind: .incrementalEverything,
            project: project,
            buildSubdir: "debug",
            options: .default
        )
        let buildDirectory = try #require(command.arguments.dropLast().firstIndex(of: "-C"))
        let ninjaPath = command.arguments[command.arguments.index(after: buildDirectory)]

        #expect(ninjaPath == project.buildRoot
            .appendingPathComponent("debug", isDirectory: true)
            .appendingPathComponent(project.swiftBuildDirectoryName, isDirectory: true)
            .path)
        #expect(ninjaPath != project.buildRoot.appendingPathComponent("debug", isDirectory: true).path)
        #expect(!command.arguments.contains("bin/swift-frontend"))
    }

    @Test func buildScriptCommandIncludesToolchainPackageAndDeploymentOptions() throws {
        let project = makeProjectInfo()
        var options = BuildOptions()
        options.installablePackage = true
        options.sccache = true
        options.installLLVM = true
        options.installSwift = true
        options.swiftTesting = true
        options.swiftTestingMacros = true
        options.installSwiftTesting = true
        options.installSwiftTestingMacros = true
        options.swiftDriver = true
        options.installSwiftDriver = true
        options.installSwiftPM = true
        options.foundation = true
        options.extraCMakeOptions = "-DPYTHON_LIBRARY=/Library/Frameworks/Python.framework/Versions/3.13/Python -DPYTHON_INCLUDE_DIR=/Library/Frameworks/Python.framework/Versions/3.13/Headers"
        options.buildSubdir = "macos-arm64"
        options.hostTarget = "macosx-arm64"
        options.stdlibDeploymentTargets = "macosx-arm64"
        options.buildSwiftDynamicStdlib = true
        options.buildSwiftDynamicSDKOverlay = true
        options.lldb = true
        options.installLLDB = true
        options.swiftDarwinSupportedArchs = "arm64"

        let command = BuildCommandBuilder.command(
            kind: .buildScript,
            project: project,
            buildSubdir: "ignored",
            options: options
        )

        #expect(command.arguments.contains("--installable-package"))
        #expect(command.arguments.contains("--skip-build-benchmarks"))
        #expect(command.arguments.contains("-r"))
        #expect(command.arguments.contains("--swift-disable-dead-stripping"))
        #expect(command.arguments.contains("--sccache"))
        #expect(command.arguments.contains("--install-llvm"))
        #expect(command.arguments.contains("--install-swift"))
        #expect(command.arguments.contains("--swift-testing"))
        #expect(command.arguments.contains("--swift-testing-macros"))
        #expect(command.arguments.contains("--install-swift-testing"))
        #expect(command.arguments.contains("--install-swift-testing-macros"))
        #expect(command.arguments.contains("--swift-driver"))
        #expect(command.arguments.contains("--install-swift-driver"))
        #expect(command.arguments.contains("--install-swiftpm"))
        #expect(command.arguments.contains("--foundation"))
        #expect(command.arguments.contains("--build-subdir=macos-arm64"))
        #expect(command.arguments.contains("--host-target=macosx-arm64"))
        #expect(command.arguments.contains("--stdlib-deployment-targets=macosx-arm64"))
        #expect(command.arguments.contains("--build-swift-dynamic-stdlib=1"))
        #expect(command.arguments.contains("--build-swift-dynamic-sdk-overlay=1"))
        #expect(command.arguments.contains("-l"))
        #expect(command.arguments.contains("--install-lldb"))
        #expect(command.arguments.contains("--swift-darwin-supported-archs"))
        #expect(command.arguments.contains("arm64"))
        #expect(command.arguments.contains("--extra-cmake-options=\(options.extraCMakeOptions)"))
    }

    @Test func customBuildScriptCommandShellParsesPastedTerminalCommand() throws {
        let project = makeProjectInfo()
        var options = BuildOptions()
        options.useCustomBuildScriptArguments = true
        options.customBuildScriptArguments = """
        ./swift/utils/build-script \\
          --installable-package \\
          --extra-cmake-options="-DPYTHON_LIBRARY=/A Path/Python -DPYTHON_INCLUDE_DIR=/Headers" \\
          --build-subdir=macos-arm64
        """

        let command = BuildCommandBuilder.command(
            kind: .buildScript,
            project: project,
            buildSubdir: "ignored",
            options: options
        )

        #expect(command.arguments == [
            "--installable-package",
            "--extra-cmake-options=-DPYTHON_LIBRARY=/A Path/Python -DPYTHON_INCLUDE_DIR=/Headers",
            "--build-subdir=macos-arm64",
        ])
    }

    @Test func buildOptionsDecodeMissingNewKeysWithDefaults() throws {
        let options = try BuildOptionsCoding.decode(Data("{}".utf8))

        #expect(options.releaseDebugInfo)
        #expect(options.assertions)
        #expect(options.swiftDisableDeadStripping)
        #expect(!options.installablePackage)
        #expect(options.jobs > 0)
    }

    @Test func lastUsedBuildSettingsStoreRoundTripsOptionsAndRepository() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var options = BuildOptions()
        options.installablePackage = true
        options.hostTarget = "macosx-arm64"
        options.extraCMakeOptions = "-DFOO=bar -DBAZ=qux"
        options.useCustomBuildScriptArguments = true
        options.customBuildScriptArguments = "--installable-package --host-target=macosx-arm64"

        LastUsedBuildSettingsStore.save(
            options: options,
            selectedRepository: "llvm-project",
            to: defaults
        )

        let loaded = try #require(LastUsedBuildSettingsStore.load(from: defaults))
        #expect(loaded.options == options)
        #expect(loaded.selectedRepository == "llvm-project")
    }

    @Test func buildJobPlannerCreatesChangedRepositoryRequestJob() throws {
        let project = makeProjectInfo()
        let operationID = UUID()
        let logPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(operationID.uuidString).log")
            .path
        let changedRepositories = [
            SwiftRepository(name: "swift", path: project.root.appendingPathComponent("swift"), currentRevision: "after"),
            SwiftRepository(name: "llvm-project", path: project.root.appendingPathComponent("llvm-project"), currentRevision: "after")
        ]
        let request = BuildRunRequest(
            operationID: operationID,
            kind: .updateAndRebuild,
            project: project,
            buildSubdir: "debug",
            options: .default,
            targetRepository: "swift",
            mode: .command(changedRepositories: changedRepositories),
            logFilePath: logPath
        )

        let job = BuildJobPlanner.job(for: request)

        #expect(job.operationID == operationID)
        #expect(job.kind == .updateAndRebuild)
        #expect(job.executable == "/bin/zsh")
        #expect(job.logFilePath == logPath)
        #expect(job.targetRepository == "swift, llvm-project")
        #expect(job.displayCommand.contains("bin/swift-frontend"))
        #expect(job.displayCommand.contains("llvm-macosx-\(ProjectService.machineArch)"))
    }

    @Test func buildRunnerWritesCarriageReturnOutputBeforeProcessExit() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftRepoGUIRunner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let logURL = root.appendingPathComponent("build.log")
        let collector = SnapshotCollector()
        let job = BuildJob(
            operationID: UUID(),
            kind: .incrementalFrontend,
            executable: "/bin/sh",
            arguments: [
                "-c",
                "printf '\\r[1/2] first'; sleep 1; printf '\\r[2/2] second\\n'"
            ],
            workingDirectory: root.path,
            displayCommand: "test carriage return output",
            logFilePath: logURL.path,
            projectPath: root.path,
            buildSubdir: "debug",
            targetRepository: "swift"
        )

        let runTask = Task {
            try await BuildProcessRunner.run(
                job: job,
                swiftSourceRoot: root.path,
                swiftBuildRoot: root.appendingPathComponent("build").path
            ) { snapshot in
                collector.append(snapshot)
            }
        }

        // Wait until the first carriage-return line has actually been drained to disk (proving the
        // log is written incrementally), instead of assuming a fixed delay — deterministic under load.
        let firstLineDeadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < firstLineDeadline {
            if (try? String(contentsOf: logURL, encoding: .utf8))?.contains("[1/2] first") == true { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let partialLog = try String(contentsOf: logURL, encoding: .utf8)
        #expect(partialLog.contains("[1/2] first"))

        let result = try await runTask.value
        let finalLog = try String(contentsOf: logURL, encoding: .utf8)
        let snapshots = collector.values()

        #expect(result.succeeded)
        #expect(finalLog.contains("[2/2] second"))
        #expect(finalLog.contains("Process exited with code 0."))
        // Progress is coalesced to ~10 Hz, so the intermediate [1/2] step may be merged into the
        // final emit when both steps arrive in a single read; the terminal [2/2] snapshot is always
        // flushed, and the log itself (asserted above) retains every line verbatim.
        #expect(snapshots.contains { $0.completedSteps == 2 && $0.totalSteps == 2 })
    }

    @Test func buildRunnerIncludesFailureOutputInResultAndLog() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftRepoGUIRunner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let logURL = root.appendingPathComponent("failed-build.log")
        let expectedError = "CMAKE_C_COMPILER is not a full path to an existing compiler tool"
        let job = BuildJob(
            operationID: UUID(),
            kind: .incrementalFrontend,
            executable: "/bin/sh",
            arguments: [
                "-c",
                "printf '%s\\n' '\(expectedError)' >&2; exit 7"
            ],
            workingDirectory: root.path,
            displayCommand: "test failing build output",
            logFilePath: logURL.path,
            projectPath: root.path,
            buildSubdir: "debug",
            targetRepository: "swift"
        )

        let result = try await BuildProcessRunner.run(
            job: job,
            swiftSourceRoot: root.path,
            swiftBuildRoot: root.appendingPathComponent("build").path
        ) { _ in }

        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(result.exitCode == 7)
        #expect(!result.succeeded)
        #expect(result.errorMessage?.contains("Process exited with code 7.") == true)
        #expect(result.errorMessage?.contains(expectedError) == true)
        #expect(log.contains(expectedError))
        #expect(log.contains("Process exited with code 7."))
    }

    @Test @MainActor func logTailReaderLoadsOnlyTailOfLargeExistingLog() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftRepoGUILogs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let logURL = root.appendingPathComponent("large.log")
        let oversizedBody = String(repeating: "a", count: Int(LogTailReader.maxBufferedBytes) * 2)
        try "prefix-marker\n\(oversizedBody)\ntail-marker\n".write(
            to: logURL,
            atomically: true,
            encoding: .utf8
        )

        let reader = LogTailReader()
        reader.track(url: logURL)
        defer { reader.stop() }
        try await waitForLogReader(reader)

        #expect(reader.isShowingTail)
        #expect(reader.text.utf8.count <= Int(LogTailReader.maxBufferedBytes))
        #expect(!reader.text.contains("prefix-marker"))
        #expect(reader.text.contains("tail-marker"))
    }

}

private final class SnapshotCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [BuildProgressSnapshot] = []

    func append(_ snapshot: BuildProgressSnapshot) {
        lock.withLock {
            storage.append(snapshot)
        }
    }

    func values() -> [BuildProgressSnapshot] {
        lock.withLock {
            storage
        }
    }
}

private func makeProjectInfo() -> SwiftProjectInfo {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SwiftRepoGUIProject-\(UUID().uuidString)", isDirectory: true)
    return makeProjectInfo(
        root: root,
        checkoutScheme: "main",
        repositories: []
    )
}

private func makeBuildJob(
    kind: BuildOperationKind,
    displayCommand: String,
    targetRepository: String = "swift"
) -> BuildJob {
    BuildJob(
        operationID: UUID(),
        kind: kind,
        executable: "/bin/sh",
        arguments: [],
        workingDirectory: "/tmp",
        displayCommand: displayCommand,
        logFilePath: "/tmp/build.log",
        projectPath: "/tmp/swift-project",
        buildSubdir: "debug",
        targetRepository: targetRepository
    )
}

private func makeProjectInfo(
    root: URL,
    checkoutScheme: String,
    repositories: [SwiftRepository]
) -> SwiftProjectInfo {
    return SwiftProjectInfo(
        root: root,
        swiftDirectory: root.appendingPathComponent("swift", isDirectory: true),
        buildScript: root.appendingPathComponent("swift/utils/build-script"),
        updateCheckout: root.appendingPathComponent("swift/utils/update-checkout"),
        buildRoot: root.appendingPathComponent("build", isDirectory: true),
        repositories: repositories,
        detectedBuildSubdirs: ["debug"],
        swiftBuildDirectoryName: "swift-\(ProjectService.platformName)-\(ProjectService.machineArch)",
        checkoutScheme: checkoutScheme,
        swiftBranch: checkoutScheme,
        schemeResolutionSource: .branchName,
        availableCheckoutSchemes: [checkoutScheme]
    )
}

private func makeSwiftDirectory(branch: String, checkoutConfig: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SwiftRepoGUITests-\(UUID().uuidString)", isDirectory: true)
    let swiftDirectory = root.appendingPathComponent("swift", isDirectory: true)
    let configDirectory = swiftDirectory
        .appendingPathComponent("utils", isDirectory: true)
        .appendingPathComponent("update_checkout", isDirectory: true)

    try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    try runGit(["init", "-b", branch], in: swiftDirectory)
    try "seed\n".write(
        to: swiftDirectory.appendingPathComponent("README.md"),
        atomically: true,
        encoding: .utf8
    )
    try runGit(["add", "README.md"], in: swiftDirectory)
    try runGit(
        ["-c", "user.name=SwiftRepoGUITests", "-c", "user.email=tests@example.com", "commit", "-m", "Initial"],
        in: swiftDirectory
    )
    try checkoutConfig.write(
        to: configDirectory.appendingPathComponent("update-checkout-config.json"),
        atomically: true,
        encoding: .utf8
    )
    return swiftDirectory
}

private func runGit(_ arguments: [String], in directory: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = directory

    let output = Pipe()
    process.standardOutput = output
    process.standardError = output

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: data, encoding: .utf8) ?? "git failed"
        throw TestCommandError(message)
    }
}

private func makeIsolatedDefaults() throws -> (UserDefaults, String) {
    let suiteName = "SwiftRepoGUITests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw TestCommandError("Could not create isolated UserDefaults.")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}

@MainActor
private func waitForLogReader(_ reader: LogTailReader) async throws {
    for _ in 0..<50 {
        if !reader.text.isEmpty || reader.readError != nil {
            return
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    throw TestCommandError("Timed out waiting for log reader.")
}

private struct TestCommandError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

@Suite struct HomeDirectoryPresetTests {
    /// Builds a throwaway directory that stands in for `~/`, writes the given files, and cleans up.
    private func withTempHome(_ files: [String: String], _ body: (URL) throws -> Void) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("homepresets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for (name, contents) in files {
            try contents.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try body(dir)
    }

    private static let overlay = """
    # Generated by SwiftBuilder — overlay preset for `build-toolchain`.

    [preset: local_buildbot_osx_package,no_test]
    mixin-preset=
        buildbot_osx_package
    swift-install-components=compiler
    """

    @Test func picksUpPresetFormattedIniAndSkipsTheRest() throws {
        try withTempHome([
            "gistya-presets.ini": Self.overlay,
            "notes.ini": "[General]\nfoo=bar\n",          // valid .ini, but no `[preset: …]` sections
            "readme.txt": Self.overlay                      // preset content, but not a .ini
        ]) { home in
            let presets = BuildPresetParser.homeDirectoryPresets(in: home)
            #expect(presets.map(\.name) == ["local_buildbot_osx_package,no_test"])
            #expect(presets.first?.mixins == ["buildbot_osx_package"])
        }
    }

    @Test func dedupesPresetNamesAcrossFilesFirstFileWins() throws {
        let dupWithDifferentMixin = """
        [preset: local_buildbot_osx_package,no_test]
        mixin-preset=
            some_other_mixin
        """
        try withTempHome([
            "a-presets.ini": Self.overlay,                 // defines local_buildbot_osx_package,no_test
            "b-presets.ini": dupWithDifferentMixin          // same preset name, scanned second
        ]) { home in
            let presets = BuildPresetParser.homeDirectoryPresets(in: home)
            #expect(presets.map(\.name) == ["local_buildbot_osx_package,no_test"])   // one entry, not two
            #expect(presets.first?.mixins == ["buildbot_osx_package"])               // the first file wins
        }
    }

    @Test func returnsEmptyForMissingDirectory() throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)", isDirectory: true)
        #expect(BuildPresetParser.homeDirectoryPresets(in: missing).isEmpty)
    }
}

@Suite struct BuildStageDetectTests {
    @Test func planSummaryLinesDoNotFlipTheStage() {
        // The one-time plan lines build-script prints at startup must NOT move the stage — matching
        // "Running Swift tests for:" is exactly what left the stage stuck on Testing through the build.
        #expect(BuildStage.detect(bannerIn: "Running Swift tests for: check-swift-validation-macosx-arm64") == nil)
        #expect(BuildStage.detect(bannerIn: "Building the standard library for: swift-stdlib-macosx-arm64") == nil)
        #expect(BuildStage.detect(bannerIn: "Running Swift benchmarks for: swiftbench") == nil)
    }

    @Test func ninjaProgressIsBuildingEvenWithGtestOnTheCommandLine() {
        // The reported regression: a stdlib compile whose command contains `-DGTEST_HAS_RTTI=0`.
        let line = "[3548/7278][ 48%][1720.206s] /opt/homebrew/bin/sccache /p/clang -DGTEST_HAS_RTTI=0 -c magic-symbols.c"
        #expect(BuildStage.detect(bannerIn: line) == .building)
        #expect(BuildStage.detect(bannerIn: "[10/20] clang -DGTEST_HAS_RTTI=0 -Werror=unused -o x.o -c x.c") == .building)
    }

    @Test func litResultLinesAreTesting() {
        #expect(BuildStage.detect(bannerIn: "PASS: Swift(macosx-arm64) :: expr/foo.swift (1 of 100)") == .testing)
        #expect(BuildStage.detect(bannerIn: "FAIL: Swift(macosx-arm64) :: crash/bar.swift") == .testing)
        #expect(BuildStage.detect(bannerIn: "XFAIL: Swift :: baz.swift") == .testing)
        #expect(BuildStage.detect(bannerIn: "UNSUPPORTED: Swift :: qux.swift") == .testing)
    }

    @Test func realBannersStillMoveTheStageButTestBannersDoNot() {
        #expect(BuildStage.detect(bannerIn: "--- Installing swift ---") == .deploying)
        #expect(BuildStage.detect(bannerIn: "--- Extracting symbols ---") == .deploying)
        #expect(BuildStage.detect(bannerIn: "--- Building foundation ---") == .building)
        #expect(BuildStage.detect(bannerIn: "--- Cleaning llbuild ---") == .building)
        // A running-tests banner does NOT force Testing; the PASS/FAIL lines will.
        #expect(BuildStage.detect(bannerIn: "--- Running tests for swift ---") == nil)
    }

    @Test func noiseKeepsTheStage() {
        #expect(BuildStage.detect(bannerIn: "-- Performing Test HAVE_CXX_FLAG - Success") == nil)  // "Test" substring
        #expect(BuildStage.detect(bannerIn: "clang: warning: argument unused") == nil)
        #expect(BuildStage.detect(bannerIn: "ld: warning: duplicate library") == nil)
    }
}
