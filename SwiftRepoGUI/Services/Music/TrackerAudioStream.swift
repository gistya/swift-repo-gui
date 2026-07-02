import AVFoundation
import Foundation

nonisolated final class TrackerAudioStream: @unchecked Sendable {
    let moduleTitle: String?
    let playerNode = AVAudioPlayerNode()
    private let core: TrackerAudioStreamCore
    var isFinished: Bool { core.isFinished }

    /// Emits a single `Void` when the stream plays to its natural end (replaying for late
    /// subscribers), then completes. Stopped/superseded streams never fire.
    var finishStream: AsyncStream<Void> { core.finishStream }

    init(
        request: TrackerStreamRequest,
        effectsSettingsBox: SoundtrackEffectsSettingsBox
    ) throws {
        let core = try TrackerAudioStreamCore(
            request: request,
            effectsSettingsBox: effectsSettingsBox
        )
        self.core = core
        moduleTitle = core.moduleTitle
    }

    func startScheduling() {
        core.startScheduling(on: playerNode)
    }

    /// Suspend until enough audio is queued to start playback (or rendering ends / the stream stops
    /// / `timeout` elapses) — the readiness stream replaces the old
    /// blocking condition-variable wait so no executor thread is held.
    func awaitReadyForPlayback(timeout: TimeInterval) async {
        let readyStream = core.readyForPlaybackStream
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in readyStream { break }
            }
            group.addTask {
                let milliseconds = max(0, Int((timeout * 1_000).rounded()))
                try? await Task.sleep(for: .milliseconds(milliseconds))
            }
            await group.next()
            group.cancelAll()
        }
    }

    @discardableResult
    func play() -> Bool {
        guard !isFinished, playerNode.engine != nil else { return false }
        if !playerNode.isPlaying {
            playerNode.play()
        }
        return true
    }

    func pause() {
        if playerNode.engine != nil, playerNode.isPlaying {
            playerNode.pause()
        }
    }

    func stop() {
        core.stop()
        if playerNode.engine != nil {
            playerNode.stop()
        }
    }

    func isConnected(to engine: AVAudioEngine) -> Bool {
        playerNode.engine === engine
    }

    deinit {
        core.stop(waitUntilSchedulerExits: false)
    }
}
