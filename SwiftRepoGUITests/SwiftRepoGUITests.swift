import Testing
import Foundation
import Ox0badf00dAVFoundation
import SwiftXState
import SwiftXStateSwiftUI
@testable import SwiftRepoGUI

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

    @Test func derivesArchitectureFromNodeNameAndLabels() {
        let arm = CIXcodeChecker.APINode(displayName: "macos-node-arm64-i-005850a", offline: false, temporarilyOffline: false, assignedLabels: [.init(name: "Xcode26")])
        #expect(CIXcodeChecker.nodeArch(arm) == "arm64")
        let intel = CIXcodeChecker.APINode(displayName: "macos-node-i-000ab41", offline: false, temporarilyOffline: false, assignedLabels: [.init(name: "macos-x86_64_Xcode-26.3")])
        #expect(CIXcodeChecker.nodeArch(intel) == "x86_64")
    }
}
