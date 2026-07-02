import Testing
import Foundation
import Ox0badf00d
import SwiftXStateSwiftUI
@testable import SwiftRepoGUI

struct SwiftRepoGUITests {

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

    @Test func buildStageClassifiesTestingAndModuleDisplay() throws {
        var context = BuildOperationsContext()
        context.activeJob = makeBuildJob(kind: .buildScript, displayCommand: "./swift/utils/build-script --test")
        context.progress = BuildProgressSnapshot(
            completedSteps: 3,
            totalSteps: 20,
            fraction: 0.15,
            etaSeconds: nil,
            message: "[3/20] Testing SwiftParseTests"
        )

        #expect(BuildStage.stage(for: context) == .testing)
        #expect(BuildStage.moduleDisplay(for: context) == "SwiftParseTests")
    }

    @Test func buildStageDisplaysPrimaryTargetInsteadOfObjectFile() throws {
        var context = BuildOperationsContext()
        context.activeJob = makeBuildJob(kind: .buildScript, displayCommand: "./swift/utils/build-script")
        context.progress = BuildProgressSnapshot(
            completedSteps: 191,
            totalSteps: 800,
            fraction: 0.23,
            etaSeconds: nil,
            message: "[191/800] Building CXX object projects/libcxx/src/CMakeFiles/cxx_shared.dir/algorithm.cpp.o"
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

    @Test func soundtrackEffectsSettingsClampRackControls() throws {
        let settings = SoundtrackEffectsSettings(
            isEnabled: true,
            drive: 4,
            lowGainDB: -50,
            midGainDB: 16,
            highGainDB: 20,
            compression: -2,
            limiterCeilingDB: -40,
            outputGainDB: 30
        ).normalized()

        #expect(settings.drive == 1)
        #expect(settings.lowGainDB == -12)
        #expect(settings.midGainDB == 12)
        #expect(settings.highGainDB == 12)
        #expect(settings.compression == 0)
        #expect(settings.limiterCeilingDB == -18)
        #expect(settings.outputGainDB == 12)
    }

    @Test func disabledSoundtrackEffectsLeaveSamplesUnchanged() throws {
        var settings = SoundtrackEffectsSettings.default
        settings.isEnabled = false
        let samples: [Float] = [0.1, -0.1, 0.35, -0.35, -0.7, 0.7, 0, 0.25]
        let buffer = PCMBuffer(sampleRate: 44_100, channelCount: 2, interleavedSamples: samples)

        let processed = SoundtrackEffectsProcessor(sampleRate: 44_100).process(buffer, settings: settings)

        #expect(processed == buffer)
    }

    @Test func soundtrackEffectsSettingsStoreRoundTripsNormalizedSettings() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var settings = SoundtrackEffectsSettings.default
        settings.isEnabled = false
        settings.drive = 0.74
        settings.lowGainDB = -3.5
        settings.limiterCeilingDB = -25

        SoundtrackEffectsSettingsStore.save(settings, to: defaults)
        let normalized = settings.normalized()

        #expect(SoundtrackEffectsSettingsStore.load(from: defaults) == normalized)
    }

    @Test func appSectionsNavigateLeftAndRightWithWraparound() throws {
        #expect(AppSectionID.build.next == .settings)
        #expect(AppSectionID.logs.next == .build)
        #expect(AppSectionID.build.previous == .logs)
        #expect(AppSectionID.history.previous == .settings)
    }

    @Test func checkoutSchemeResolverUsesUnmatchedCurrentSwiftBranch() throws {
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

        let resolution = CheckoutSchemeResolver.resolve(swiftDirectory: swiftDirectory)

        #expect(resolution.scheme == "feature/current-branch")
        #expect(resolution.branch == "feature/current-branch")
        #expect(resolution.source == .branchFallback)
        #expect(CheckoutSchemeResolver.availableSchemes(swiftDirectory: swiftDirectory).contains("feature/current-branch"))
    }

    @Test func checkoutSchemeResolverUsesBranchPointingAtDetachedHead() throws {
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

        let resolution = CheckoutSchemeResolver.resolve(swiftDirectory: swiftDirectory)

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

    @Test @MainActor func appSessionRestoresLastUsedBuildSettingsOnLaunch() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var options = BuildOptions()
        options.foundation = true
        options.installSwiftPM = true
        options.buildSubdir = "macos-arm64"
        LastUsedBuildSettingsStore.save(
            options: options,
            selectedRepository: "swift-package-manager",
            to: defaults
        )

        let session = AppSession(settingsDefaults: defaults)

        try await waitForSettings(session, options: options, selectedRepository: "swift-package-manager")
        #expect(session.settings.context.options == options)
        #expect(session.settings.context.selectedRepository == "swift-package-manager")
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

        try await Task.sleep(for: .milliseconds(300))
        let partialLog = try String(contentsOf: logURL, encoding: .utf8)
        #expect(partialLog.contains("[1/2] first"))

        let result = try await runTask.value
        let finalLog = try String(contentsOf: logURL, encoding: .utf8)
        let snapshots = collector.values()

        #expect(result.succeeded)
        #expect(finalLog.contains("[2/2] second"))
        #expect(finalLog.contains("Process exited with code 0."))
        #expect(snapshots.contains { $0.completedSteps == 1 && $0.totalSteps == 2 })
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
private func waitForSettings(
    _ session: AppSession,
    options: BuildOptions,
    selectedRepository: String
) async throws {
    for _ in 0..<50 {
        if session.settings.context.options == options,
           session.settings.context.selectedRepository == selectedRepository {
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
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
