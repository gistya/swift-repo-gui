import Testing
import Foundation
import Ox0badf00dAVFoundation
import SwiftXState
import SwiftXStateSwiftUI
@testable import SwiftBuild

@Suite(.serialized)
struct SwiftRepoGUITests {
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
    
    @Test func buildEventsDoNotRecueSoundtrack() throws {
        let track = TrackerModuleTrack(
            url: URL(fileURLWithPath: "/tmp/flicker.xm"),
            fileName: "flicker.xm",
            title: "flicker",
            format: "XM"
        )
        let soundStyle = MusicSettings.current
        let context = SoundtrackContext(
            isMuted: false,
            tracks: [track],
            volume: Double(soundStyle.masterVolume),
            soundStyle: soundStyle
        )
        let machine = SoundtrackMachine(context: context)
        let schema = machine.buildSchema()
        let resolved = schema.resolve(id: "soundtrack-build-\(UUID().uuidString)", context: context)
        var snapshot = initialTransition(resolved).snapshot

        // Launch cues a startup track and we confirm it's playing.
        snapshot = transition(resolved, snapshot: snapshot, event: SoundtrackEvent.launch.event).snapshot
        guard case let .play(_, generation, _)? = snapshot.context.pendingAudioRequest?.command else {
            Issue.record("Launch should cue a startup track.")
            return
        }
        snapshot = transition(
            resolved,
            snapshot: snapshot,
            event: SoundtrackEvent.playbackPrepared(moduleTitle: "flicker", generation: generation, started: true).event
        ).snapshot
        #expect(schema.configuration(from: snapshot.value)?.matches(.playing) == true)
        let stableGeneration = snapshot.context.generation

        // A whole build lifecycle — start, noisy sub-stage flicker, then success — must NOT change
        // the track. Track changes are wired only to natural track-end for now; the build-transition
        // signalling hooks are deliberately dormant. (This is also the regression guard for the
        // CoreAudio flood: re-cueing on stage flicker drove rapid engine.play() calls.)
        let buildEvents: [SoundtrackBuildSnapshot] = [
            SoundtrackBuildSnapshot(stage: .building, isRunning: true, succeeded: false),
            SoundtrackBuildSnapshot(stage: .testing, isRunning: true, succeeded: false),
            SoundtrackBuildSnapshot(stage: .deploying, isRunning: true, succeeded: false),
            SoundtrackBuildSnapshot(stage: .building, isRunning: true, succeeded: false),
            SoundtrackBuildSnapshot(stage: .testing, isRunning: true, succeeded: false),
            SoundtrackBuildSnapshot(stage: .off, isRunning: false, succeeded: true),
        ]
        for build in buildEvents {
            snapshot = transition(
                resolved,
                snapshot: snapshot,
                event: SoundtrackEvent.buildSnapshotChanged(build).event
            ).snapshot
        }

        #expect(snapshot.context.generation == stableGeneration)
        #expect(schema.configuration(from: snapshot.value)?.matches(.playing) == false)
    }

    @Test func soundtrackMachineQueuesAudioCommandsBeforeConfirmedPlaybackStateChanges() throws {
        let track = TrackerModuleTrack(
            url: URL(fileURLWithPath: "/tmp/drozerix_-_bubble_machine.xm"),
            fileName: "drozerix_-_bubble_machine.xm",
            title: "drozerix_-_bubble_machine",
            format: "XM"
        )
        let soundStyle = MusicSettings.current
        let context = SoundtrackContext(
            isMuted: false,
            tracks: [track],
            volume: Double(soundStyle.masterVolume),
            soundStyle: soundStyle
        )
        let machine = SoundtrackMachine(context: context)
        let schema = machine.buildSchema()
        let resolvedMachine = schema.resolve(
            id: "soundtrack-test-\(UUID().uuidString)",
            context: context
        )
        var snapshot = initialTransition(resolvedMachine).snapshot

        snapshot = transition(resolvedMachine, snapshot: snapshot, event: SoundtrackEvent.launch.event).snapshot

        let loadingContext = snapshot.context
        let loadingConfiguration = schema.configuration(from: snapshot.value)
        if loadingConfiguration?.matches(.loading) != true {
            Issue.record("After launch: value=\(snapshot.value), configuration=\(String(describing: loadingConfiguration)), context=\(loadingContext)")
        }
        #expect(loadingConfiguration?.matches(.loading) == true)
        guard case let .play(_, generation, startImmediately)? = loadingContext.pendingAudioRequest?.command else {
            Issue.record("Launch should queue a play command.")
            return
        }
        #expect(startImmediately)

        snapshot = transition(
            resolvedMachine,
            snapshot: snapshot,
            event: SoundtrackEvent.playbackPrepared(
                moduleTitle: "Bubble Machine!",
                generation: generation,
                started: true
            ).event
        ).snapshot
        #expect(schema.configuration(from: snapshot.value)?.matches(.playing) == true)
        #expect(snapshot.context.nowPlaying.title == "Bubble Machine!")

        snapshot = transition(resolvedMachine, snapshot: snapshot, event: SoundtrackEvent.togglePause.event).snapshot
        #expect(schema.configuration(from: snapshot.value)?.matches(.playing) == true)
        let pauseContext = snapshot.context
        guard case let .pause(pauseGeneration)? = pauseContext.pendingAudioRequest?.command else {
            Issue.record("Pause should queue a pause command before the machine enters paused.")
            return
        }

        snapshot = transition(
            resolvedMachine,
            snapshot: snapshot,
            event: SoundtrackEvent.playbackPaused(generation: pauseGeneration).event
        ).snapshot
        #expect(schema.configuration(from: snapshot.value)?.matches(.paused) == true)
    }
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

private func makeIsolatedDefaults() throws -> (UserDefaults, String) {
    let suiteName = "SwiftRepoGUITests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw TestCommandError("Could not create isolated UserDefaults.")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}

private struct TestCommandError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

@Suite struct CIXcodeCheckerTests {
    /// Verbatim from `ci.swift.org/api/json?tree=primaryView[description]` (2026-07-19), including
    /// the commented-out banner and the icon URL that both mention "xcode".
    private static let dashboardDescription = """
    <!-- <h2 id="shutdown-msg"> <img style="height: 64px" src="https://developer.apple.com/assets/elements/icons/xcode/xcode-64x64_2x.png"> Updating Xcode/OS </h2>-->
    <h4>Visit <a href="https://swift.org">swift.org</a> for more details about the Swift project</h4>

    <h4> Node information </h4>

    <strong> macOS </strong>
    <p> Host OS: macOS 15.1.1 <br>
      Xcode 16.2 <a href="https://developer.apple.com/">(Download Link)</a>
    </p>

    <strong> Linux</strong>
    <p>Ubuntu 20.04 (Pull Request)<br>
    """

    @Test func parsesCIXcodeFromTheDashboardNodeInformationBlock() throws {
        let parsed = try #require(
            CIXcodeChecker.parseCIXcode(fromDashboardDescription: Self.dashboardDescription)
        )
        // NOT "64" from the xcode-64x64_2x.png icon URL inside the HTML comment.
        #expect(parsed.xcode == "16.2")
        #expect(parsed.hostOS == "15.1.1")
    }

    /// The commented-out "Updating Xcode/OS" banner is periodically re-enabled by the Swift CI folks;
    /// a stray version inside it must never be mistaken for the live one.
    @Test func ignoresXcodeMentionsInsideHTMLComments() throws {
        let html = """
        <!-- <h2> Updating to Xcode 99.9 </h2> -->
        <h4> Node information </h4>
        <p> Host OS: macOS 15.1.1 <br> Xcode 16.2 </p>
        """
        let parsed = try #require(CIXcodeChecker.parseCIXcode(fromDashboardDescription: html))
        #expect(parsed.xcode == "16.2")
    }

    @Test func returnsNothingWhenTheDashboardStatesNoXcode() {
        #expect(CIXcodeChecker.parseCIXcode(fromDashboardDescription: "<h4>Visit swift.org</h4>") == nil)
    }

    @Test func parsesLocalXcodebuildOutput() throws {
        let parsed = try #require(CIXcodeChecker.parseLocalXcode(fromXcodebuildOutput: "Xcode 26.3\nBuild version 17C529"))
        #expect(parsed.version == "26.3")
        #expect(parsed.build == "17C529")
    }

    @Test func matchesCILabelAtAvailablePrecision() {
        let local = try! #require(XcodeVersion(parsingVersionString: "26.3"))
        // Major-only CI label matches any minor of the same major.
        #expect(local.matchesCILabel(XcodeVersion(major: 26, minor: nil)))
        // Exact same minor matches.
        #expect(local.matchesCILabel(XcodeVersion(major: 26, minor: 3)))
        // Different minor does NOT match when the CI label carries one.
        #expect(!local.matchesCILabel(XcodeVersion(major: 26, minor: 2)))
        // Different major never matches.
        #expect(!local.matchesCILabel(XcodeVersion(major: 16, minor: 2)))
    }

    @Test func parsesXcodeLabelsAcrossFormats() {
        #expect(CIXcodeChecker.parseXcodeVersion(fromLabel: "Xcode26") == XcodeVersion(major: 26, minor: nil))
        #expect(CIXcodeChecker.parseXcodeVersion(fromLabel: "Xcode-26.3") == XcodeVersion(major: 26, minor: 3))
        #expect(CIXcodeChecker.parseXcodeVersion(fromLabel: "Xcode-16.2") == XcodeVersion(major: 16, minor: 2))
        #expect(CIXcodeChecker.parseXcodeVersion(fromLabel: "Xcode15.2b") == XcodeVersion(major: 15, minor: 2, isBeta: true))
        // Composite node label still yields the embedded version.
        #expect(CIXcodeChecker.parseXcodeVersion(fromLabel: "macos-x86_64_Xcode-26.3") == XcodeVersion(major: 26, minor: 3))
        // Non-Xcode labels yield nothing.
        #expect(CIXcodeChecker.parseXcodeVersion(fromLabel: "arm64") == nil)
        #expect(CIXcodeChecker.parseXcodeVersion(fromLabel: "macOS-26.2") == nil)
    }

    @Test func derivesArchitectureFromNodeNameAndLabels() {
        let arm = CIXcodeChecker.APINode(displayName: "macos-node-arm64-i-005850a", offline: false, temporarilyOffline: false, assignedLabels: [.init(name: "Xcode26")])
        #expect(CIXcodeChecker.nodeArch(arm) == "arm64")
        #expect(CIXcodeChecker.nodeArch(arm) == CIFleet.appleSilicon.arch)
        let intel = CIXcodeChecker.APINode(displayName: "macos-node-i-000ab41", offline: false, temporarilyOffline: false, assignedLabels: [.init(name: "macos-x86_64_Xcode-26.3")])
        #expect(CIXcodeChecker.nodeArch(intel) == "x86_64")
        #expect(CIXcodeChecker.nodeArch(intel) == CIFleet.intel.arch)
    }

    /// The fleet choice persists, and an unset/garbage value falls back to this machine's own arch
    /// rather than silently comparing against the other architecture's machines.
    @Test func fleetSelectionPersistsAndDefaultsToThisMachine() throws {
        let defaults = try #require(UserDefaults(suiteName: "CIFleetTests-\(UUID().uuidString)"))
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        #expect(CIFleet.current(defaults) == .local)
        defaults.set(CIFleet.intel.rawValue, forKey: CIFleet.defaultsKey)
        #expect(CIFleet.current(defaults) == .intel)
        defaults.set("sparc", forKey: CIFleet.defaultsKey)
        #expect(CIFleet.current(defaults) == .local)
    }

    /// Switching fleet must invalidate a cached verdict — the pools run different Xcodes, so reusing
    /// the previous fleet's result would show a confidently wrong answer.
    @Test func changingEitherTheToolchainOrTheFleetInvalidatesTheResult() {
        let xcode26 = ToolchainSelection(developerDir: "/Applications/Xcode.app")
        let xcode16 = ToolchainSelection(developerDir: "/Applications/Xcode-16.2.app")
        let arm = CIXcodeCheckInputs(toolchain: xcode26, fleet: .appleSilicon)
        let status = CIXcodeStatus(
            localVersion: "26.3", localBuild: "17C529", fleet: .appleSilicon,
            primaryCIVersion: "Xcode 26", ciVersions: ["Xcode 26"],
            matches: true, comparedAtMajorOnly: true,
            publishedVersion: "16.2", publishedHostOS: "15.1.1"
        )
        let loaded = CIXcodeCheckState.loaded(status)

        #expect(!loaded.shouldAutoCheck(checked: arm, current: arm))
        // Same Xcode, different fleet.
        #expect(loaded.shouldAutoCheck(
            checked: arm, current: CIXcodeCheckInputs(toolchain: xcode26, fleet: .intel)
        ))
        // Same fleet, different Xcode.
        #expect(loaded.shouldAutoCheck(
            checked: arm, current: CIXcodeCheckInputs(toolchain: xcode16, fleet: .appleSilicon)
        ))
    }

    /// The arm64 fleet is labelled `Xcode26` while the dashboard blurb states 16.2 — a real, current
    /// disagreement the banner must call out instead of hiding.
    @Test func flagsWhenThePublishedVersionDisagreesWithTheFleet() throws {
        let published = try #require(
            CIXcodeChecker.parseCIXcode(fromDashboardDescription: Self.dashboardDescription)
        )
        func status(fleetPrimary: String) -> CIXcodeStatus {
            CIXcodeStatus(
                localVersion: "26.3", localBuild: nil, fleet: .appleSilicon,
                primaryCIVersion: fleetPrimary, ciVersions: [fleetPrimary],
                matches: true, comparedAtMajorOnly: false,
                publishedVersion: published.xcode, publishedHostOS: published.hostOS
            )
        }
        #expect(status(fleetPrimary: "Xcode 26").publishedDiffersFromFleet)
        #expect(!status(fleetPrimary: "Xcode 16.2").publishedDiffersFromFleet)
    }

    /// The check used to run once per launch and never again, so switching Xcode in Build Settings
    /// left a verdict about the PREVIOUS Xcode on screen, and a transient network failure hid the
    /// banner (and its Recheck button) for the rest of the session.
    @Test func autoCheckRerunsWhenTheToolchainSelectionChangesButNotOtherwise() {
        let a = CIXcodeCheckInputs(
            toolchain: ToolchainSelection(developerDir: "/Applications/Xcode.app"), fleet: .appleSilicon
        )
        let b = CIXcodeCheckInputs(
            toolchain: ToolchainSelection(developerDir: "/Applications/Xcode-16.2.app"), fleet: .appleSilicon
        )
        let status = CIXcodeStatus(
            localVersion: "26.3", localBuild: "17C529", fleet: .appleSilicon,
            primaryCIVersion: "Xcode 26", ciVersions: ["Xcode 26"],
            matches: true, comparedAtMajorOnly: true,
            publishedVersion: "16.2", publishedHostOS: "15.1.1"
        )

        // Nothing has run yet.
        #expect(CIXcodeCheckState.idle.shouldAutoCheck(checked: nil, current: a))
        // A result for the CURRENT inputs is not recomputed on every tab visit.
        #expect(!CIXcodeCheckState.loaded(status).shouldAutoCheck(checked: a, current: a))
        // ...but a result for DIFFERENT inputs is stale and must be refreshed.
        #expect(CIXcodeCheckState.loaded(status).shouldAutoCheck(checked: a, current: b))
        // An in-flight check isn't restarted underneath itself.
        #expect(!CIXcodeCheckState.checking.shouldAutoCheck(checked: a, current: a))
        // A failure waits for the explicit Recheck button rather than re-timing-out per tab switch,
        // but still refreshes if the selection moved on.
        #expect(!CIXcodeCheckState.failed.shouldAutoCheck(checked: a, current: a))
        #expect(CIXcodeCheckState.failed.shouldAutoCheck(checked: a, current: b))
    }

    @Test func onlyALoadedCheckCarriesAStatus() {
        let status = CIXcodeStatus(
            localVersion: "26.3", localBuild: nil, fleet: .intel,
            primaryCIVersion: "Xcode 16.2", ciVersions: ["Xcode 16.2"],
            matches: false, comparedAtMajorOnly: false,
            publishedVersion: "16.2", publishedHostOS: "15.1.1"
        )
        #expect(CIXcodeCheckState.loaded(status).status == status)
        #expect(CIXcodeCheckState.idle.status == nil)
        #expect(CIXcodeCheckState.checking.status == nil)
        #expect(CIXcodeCheckState.failed.status == nil)
    }
}

@Suite struct PythonSelectionTests {
    private func python(_ dir: String, _ version: String) -> InstalledPython {
        let parts = version.split(separator: ".").map { Int($0) ?? 0 }
        return InstalledPython(
            binDirectory: dir, version: version,
            major: parts[0], minor: parts[1], patch: parts.count > 2 ? parts[2] : 0
        )
    }

    @Test func parsesInterpreterVersionOutput() throws {
        let parsed = try #require(InstalledPythons.parseVersion(fromVersionOutput: "Python 3.13.14\n"))
        #expect((parsed.major, parsed.minor, parsed.patch) == (3, 13, 14))
        #expect(parsed.full == "3.13.14")
        // Some builds report only major.minor.
        let short = try #require(InstalledPythons.parseVersion(fromVersionOutput: "Python 3.14"))
        #expect((short.major, short.minor, short.patch) == (3, 14, 0))
        #expect(InstalledPythons.parseVersion(fromVersionOutput: "bash: python3: not found") == nil)
    }

    /// The point of the setting: installing a newer Python must not take over builds.
    @Test func automaticPicksNewest313AndIgnoresNewerReleases() {
        let installed = [
            python("/opt/homebrew/bin", "3.14.6"),
            python("/Library/Frameworks/Python.framework/Versions/3.13/bin", "3.13.14"),
            python("/old/bin", "3.13.2"),
            python("/usr/bin", "3.9.6"),
        ]
        let choice = PythonSelection.automaticChoice(among: installed)
        #expect(choice?.version == "3.13.14")
        #expect(PythonSelection.automatic.resolvedBinDirectory(installed: installed)
            == "/Library/Frameworks/Python.framework/Versions/3.13/bin")
    }

    /// If the preferred release isn't installed, leave PATH alone rather than silently substituting
    /// some other interpreter.
    @Test func automaticChangesNothingWhenThePreferredVersionIsAbsent() {
        let installed = [python("/opt/homebrew/bin", "3.14.6"), python("/usr/bin", "3.9.6")]
        #expect(PythonSelection.automatic.resolvedBinDirectory(installed: installed) == nil)

        var environment = ["PATH": "/usr/bin:/bin"]
        PythonSelection.automatic.apply(to: &environment, installed: installed)
        #expect(environment["PATH"] == "/usr/bin:/bin")
    }

    /// The ordering trap: an Xcode's Developer/usr/bin also ships a python3 (3.9.6), so the chosen
    /// interpreter has to end up AHEAD of the toolchain directories, not behind them.
    @Test func chosenInterpreterOutranksAnXcodesBundledPython3() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("python-\(UUID().uuidString)", isDirectory: true)
        let bin = root.appendingPathComponent("Versions/3.13/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let executable = bin.appendingPathComponent("python3")
        FileManager.default.createFile(atPath: executable.path, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: root) }

        let xcodeBin = "/Applications/Xcode.app/Contents/Developer/usr/bin"
        var environment = ["PATH": "/usr/bin:/bin"]
        // Same order the build runner uses: toolchain first, then Python.
        PathEnvironment.frontLoad([xcodeBin], in: &environment)
        PythonSelection(binDirectory: bin.path).apply(
            to: &environment, installed: [python(bin.path, "3.13.14")]
        )

        let entries = try #require(environment["PATH"]).split(separator: ":").map(String.init)
        let pythonIndex = try #require(entries.firstIndex(of: bin.path))
        let xcodeIndex = try #require(entries.firstIndex(of: xcodeBin))
        #expect(pythonIndex < xcodeIndex)
        #expect(entries.suffix(2) == ["/usr/bin", "/bin"])
    }

    /// An explicitly chosen directory that has been uninstalled must not fall back to a different
    /// interpreter — that would reintroduce exactly the surprise this setting prevents.
    @Test func anExplicitChoiceThatNoLongerExistsLeavesPathUntouched() {
        let installed = [python("/Library/Frameworks/Python.framework/Versions/3.13/bin", "3.13.14")]
        let selection = PythonSelection(binDirectory: "/gone/3.13/bin")
        #expect(selection.resolvedBinDirectory(installed: installed) == nil)

        var environment = ["PATH": "/usr/bin:/bin"]
        selection.apply(to: &environment, installed: installed)
        #expect(environment["PATH"] == "/usr/bin:/bin")
    }

    @Test func frontLoadingPreservesOrderAndDropsDuplicates() {
        var environment = ["PATH": "/usr/bin:/bin:/opt/homebrew/bin"]
        PathEnvironment.frontLoad(["/first", "/second", "/opt/homebrew/bin"], in: &environment)
        #expect(environment["PATH"] == "/first:/second:/opt/homebrew/bin:/usr/bin:/bin")
    }

    /// Discovery must only offer directories that provide `python3` specifically — Homebrew's
    /// libexec/bin has `python` but no `python3`, so it cannot satisfy the scripts' shebang.
    @Test func discoveredInterpretersAreRealAndProvidePython3() {
        for python in InstalledPythons.discover() {
            #expect(FileManager.default.isExecutableFile(atPath: python.executablePath))
            #expect(python.major == 3)
        }
    }
}

@Suite struct ToolchainSelectionTests {
    @Test func resolvesDeveloperDirFromAppPathOrDeveloperDir() {
        #expect(ToolchainSelection(developerDir: "/Applications/Xcode_16.2.app").resolvedDeveloperDir
                == "/Applications/Xcode_16.2.app/Contents/Developer")
        #expect(ToolchainSelection(developerDir: "/Applications/Xcode.app/Contents/Developer").resolvedDeveloperDir
                == "/Applications/Xcode.app/Contents/Developer")
        #expect(ToolchainSelection().resolvedDeveloperDir == nil)
        #expect(ToolchainSelection(developerDir: "   ").resolvedDeveloperDir == nil)
    }

    @Test func applyPinsTheChosenToolchainWithoutDisturbingTheRestOfTheEnvironment() {
        var environment = ["PATH": "/usr/bin"]
        // Deliberately a path that doesn't exist: the env vars are still pinned, while PATH gains
        // nothing (only real directories are front-loaded) — which keeps this deterministic anywhere.
        ToolchainSelection(
            developerDir: "/Applications/DoesNotExist.app",
            toolchainIdentifier: "org.example.absent"
        ).apply(to: &environment, toolchains: [])
        #expect(environment["DEVELOPER_DIR"] == "/Applications/DoesNotExist.app/Contents/Developer")
        #expect(environment["TOOLCHAINS"] == "org.example.absent")
        #expect(environment["PATH"] == "/usr/bin")
    }

    @Test func applyClearsInheritedEnvironmentWhenNothingIsSelected() {
        // The whole point of choosing in-app: a build must not silently inherit the launching shell's
        // Xcode. "System default" means xcode-select, deterministically.
        var environment = [
            "DEVELOPER_DIR": "/Applications/Xcode_16.2.app/Contents/Developer",
            "TOOLCHAINS": "org.swift.whatever",
            "PATH": "/usr/bin"
        ]
        ToolchainSelection.systemDefault.apply(to: &environment, toolchains: [])
        #expect(environment["DEVELOPER_DIR"] == nil)
        #expect(environment["TOOLCHAINS"] == nil)
        #expect(environment["PATH"] == "/usr/bin")
    }

    @Test func applyFrontLoadsPathWithTheChosenToolchainBin() throws {
        // Real directories (the existence filter has to pass) but under a temp root, so the assertion
        // is deterministic rather than depending on what happens to be installed on this Mac.
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("toolchain-\(UUID().uuidString)", isDirectory: true)
        let toolchainPath = root.appendingPathComponent("Fake.xctoolchain", isDirectory: true)
        let toolchainBin = toolchainPath.appendingPathComponent("usr/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: toolchainBin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var environment = ["PATH": "/usr/bin:/bin"]
        ToolchainSelection(toolchainIdentifier: "com.example.fake").apply(
            to: &environment,
            toolchains: [InstalledToolchain(identifier: "com.example.fake", name: "Fake", path: toolchainPath.path)]
        )
        // The chosen toolchain's bin outranks whatever shim was already on PATH…
        #expect(environment["PATH"]?.hasPrefix(toolchainBin.path + ":") == true)
        // …and the original entries survive after it.
        #expect(environment["PATH"]?.hasSuffix("/usr/bin:/bin") == true)
    }

    @Test func discoveredXcodesAreRealAndUnique() {
        // Invariant-based rather than machine-specific, so this can't go flaky on another Mac.
        let xcodes = InstalledDeveloperTools.xcodes()
        for xcode in xcodes {
            #expect(FileManager.default.fileExists(atPath: xcode.developerDir + "/usr/bin/xcodebuild"))
            #expect(!xcode.version.isEmpty)
        }
        #expect(Set(xcodes.map(\.id)).count == xcodes.count)
    }

    @Test func discoveredToolchainsAreDedupedByIdentifier() {
        // e.g. swift-latest.xctoolchain aliases another toolchain and shares its identifier.
        let toolchains = InstalledDeveloperTools.toolchains()
        #expect(Set(toolchains.map(\.identifier)).count == toolchains.count)
        for toolchain in toolchains {
            #expect(!toolchain.identifier.isEmpty)
            #expect(FileManager.default.fileExists(atPath: toolchain.path))
        }
    }
}
