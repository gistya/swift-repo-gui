import AVFoundation
import XCTest
@testable import Ox0badf00d

/// Reproduces "plays ~0.5s then stops but state stays playing": samples the live mixer output in time
/// windows and the engine's pump counters, to see whether playback continues past the initial
/// pre-roll (`scheduleAheadBuffers` × `renderChunkFrames`) or the completion-driven refill stalls.
final class PumpContinuityTests: XCTestCase {
    private final class WindowProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var sumSq: Double = 0
        private var count = 0
        func add(_ buffer: AVAudioPCMBuffer) {
            guard let d = buffer.floatChannelData else { return }
            let ch = Int(buffer.format.channelCount), n = Int(buffer.frameLength)
            lock.lock(); defer { lock.unlock() }
            for c in 0..<ch { let p = d[c]; for f in 0..<n { sumSq += Double(p[f]) * Double(p[f]); count += 1 } }
        }
        func drainRMS() -> Float {
            lock.lock(); defer { lock.unlock() }
            let rms = count > 0 ? Float((sumSq / Double(count)).squareRoot()) : 0
            sumSq = 0; count = 0
            return rms
        }
    }

    func testPlaybackContinuesPastPreroll() async throws {
        let url = URL(fileURLWithPath: "/Users/shad/dev/originalPublic/swift-repo-gui/SwiftRepoGUI/Resources/TrackerModules/drozerix_-_stardust_jam.mod")
        let config = AudioSessionConfig(
            sampleRate: 44_100, channelCount: 2, renderChunkFrames: 8_192, scheduleAheadBuffers: 3,
            gain: 1, spatialization: .psychoacoustic3D(.spacious)
        )
        let engine = TrackerAudioEngine(config: config)
        let probe = WindowProbe()
        await engine._installOutputTap { probe.add($0) }
        await engine.play(moduleURL: url, generation: 1, startImmediately: true)

        // Sample ~250ms windows out to ~2.5s.
        for window in 0..<10 {
            try await Task.sleep(for: .milliseconds(250))
            let rms = probe.drainRMS()
            let s = await engine._pumpState()
            print("### t≈\(Double(window + 1) * 0.25)s rms=\(String(format: "%.4f", rms)) rendered=\(s.rendered) inFlight=\(s.inFlight) final=\(s.final) running=\(s.running) playing=\(s.playing)")
        }
        await engine.stop(generation: 1)
    }

    /// A configuration change must not kill playback: after recovery the pump keeps refilling and the
    /// mixer keeps producing audio.
    func testRecoversFromConfigurationChange() async throws {
        let url = URL(fileURLWithPath: "/Users/shad/dev/originalPublic/swift-repo-gui/SwiftRepoGUI/Resources/TrackerModules/drozerix_-_stardust_jam.mod")
        let engine = TrackerAudioEngine(config: AudioSessionConfig(gain: 1))
        let probe = WindowProbe()
        await engine._installOutputTap { probe.add($0) }
        await engine.play(moduleURL: url, generation: 1, startImmediately: true)

        try await Task.sleep(for: .milliseconds(400))
        _ = probe.drainRMS()
        await engine._simulateConfigurationChange()

        // After the (simulated) change, audio must keep flowing across the next second.
        var afterRMS: [Float] = []
        for _ in 0..<3 {
            try await Task.sleep(for: .milliseconds(300))
            afterRMS.append(probe.drainRMS())
        }
        let s = await engine._pumpState()
        print("### post-configchange rms=\(afterRMS.map { String(format: "%.4f", $0) }) rendered=\(s.rendered) playing=\(s.playing)")
        await engine.stop(generation: 1)

        XCTAssertTrue(afterRMS.allSatisfy { $0 > 0.001 }, "playback died after configuration change: \(afterRMS)")
    }

    /// The REAL config-change path: the engine actually STOPS first (as it does on a device/format
    /// change), then the handler must restart it and resume audio. The earlier test left the engine
    /// running, so it never exercised the restart.
    func testRecoversWhenEngineActuallyStopped() async throws {
        let url = URL(fileURLWithPath: "/Users/shad/dev/originalPublic/swift-repo-gui/SwiftRepoGUI/Resources/TrackerModules/drozerix_-_stardust_jam.mod")
        let engine = TrackerAudioEngine(config: AudioSessionConfig(gain: 1))
        let probe = WindowProbe()
        await engine._installOutputTap { probe.add($0) }
        await engine.play(moduleURL: url, generation: 1, startImmediately: true)
        try await Task.sleep(for: .milliseconds(400))

        // Simulate the engine stop a real config change causes, then confirm it is stopped...
        await engine._stopEngineForTest()
        let stoppedRunning = await engine._engineRunning()
        try await Task.sleep(for: .milliseconds(300))
        _ = probe.drainRMS()
        // ...then fire the handler and verify audio comes back.
        await engine._simulateConfigurationChange()
        let afterRunning = await engine._engineRunning()

        var afterRMS: [Float] = []
        for _ in 0..<3 {
            try await Task.sleep(for: .milliseconds(300))
            afterRMS.append(probe.drainRMS())
        }
        print("### engine-stop recovery: stoppedRunning=\(stoppedRunning) afterRunning=\(afterRunning) rms=\(afterRMS.map { String(format: "%.4f", $0) })")
        await engine.stop(generation: 1)

        XCTAssertFalse(stoppedRunning, "engine did not actually stop")
        XCTAssertTrue(afterRunning, "engine not restarted after recovery")
        XCTAssertTrue(afterRMS.allSatisfy { $0 > 0.001 }, "no audio after restart recovery: \(afterRMS)")
    }

    /// The actual app-launch fix: if the player node stops out from under us while the engine keeps
    /// running (the startup completion-refill race), the watchdog must notice and resume playback.
    func testWatchdogResumesAfterPlayerStops() async throws {
        let url = URL(fileURLWithPath: "/Users/shad/dev/originalPublic/swift-repo-gui/SwiftRepoGUI/Resources/TrackerModules/drozerix_-_stardust_jam.mod")
        let engine = TrackerAudioEngine(config: AudioSessionConfig(gain: 1))
        let probe = WindowProbe()
        await engine._installOutputTap { probe.add($0) }
        await engine.play(moduleURL: url, generation: 1, startImmediately: true)
        try await Task.sleep(for: .milliseconds(400))

        // Simulate AVAudioPlayerNode stopping unexpectedly (engine stays up).
        await engine._stopPlayerForTest()
        let stoppedPlaying = await engine._playerPlaying()
        XCTAssertFalse(stoppedPlaying, "player did not stop")
        _ = probe.drainRMS()

        // The 250ms watchdog should re-prime and resume within ~1s.
        var afterRMS: [Float] = []
        for _ in 0..<3 {
            try await Task.sleep(for: .milliseconds(350))
            afterRMS.append(probe.drainRMS())
        }
        let resumedPlaying = await engine._playerPlaying()
        print("### watchdog resume: resumedPlaying=\(resumedPlaying) rms=\(afterRMS.map { String(format: "%.4f", $0) })")
        await engine.stop(generation: 1)

        XCTAssertTrue(resumedPlaying, "watchdog did not resume the player")
        XCTAssertTrue(afterRMS.contains { $0 > 0.001 }, "no audio after watchdog recovery: \(afterRMS)")
    }
}
