import AVFoundation
import Foundation

nonisolated final class TrackerAudioStream: @unchecked Sendable {
    let moduleTitle: String?
    let playerNode = AVAudioPlayerNode()
    private let core: TrackerAudioStreamCore
    var isFinished: Bool { core.isFinished }

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

    func waitUntilReadyForPlayback(timeout: TimeInterval) {
        core.waitUntilReadyForPlayback(timeout: timeout)
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
