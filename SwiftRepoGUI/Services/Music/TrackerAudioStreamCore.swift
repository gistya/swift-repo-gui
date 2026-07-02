import AVFoundation
import Foundation
import Ox0badf00d

nonisolated final class TrackerAudioStreamCore: @unchecked Sendable {
    let request: TrackerStreamRequest
    let moduleTitle: String?
    private let renderer: ModuleRenderer
    private let effectsProcessor: SoundtrackEffectsProcessor
    private let effectsSettingsBox: SoundtrackEffectsSettingsBox
    private let format: AVAudioFormat
    private let renderChunkFrameCount: Int
    private let playbackStartFrameCount: Int
    private let maxQueuedFrameCount: Int
    private let maxFrameCount: Int
    private let finishFlag = SoundtrackStreamFinishFlag()
    /// One-shot readiness: flips to true when enough frames are queued to start playback (or the
    /// track renders out before reaching the preroll threshold, or the stream stops).
    private let readySignal = AsyncOneShotSignal()
    private let condition = NSCondition()
    private let completionQueue = DispatchQueue(label: "SwiftBuilder.TrackerAudioStream.Completions", qos: .default) // .userInitiated caused issues
    private weak var playerNode: AVAudioPlayerNode?
    private var renderedFrameCount = 0
    private var queuedFrameCount = 0
    private var didRenderFinalBuffer = false
    private var didFinish = false
    private var didStartRendering = false
    private var didExitScheduling = false
    private var stopRequested = false
    var isFinished: Bool { finishFlag.isFinished }

    /// Emits a single `Void` when the stream has played to its natural end, then completes.
    /// Replays for late subscribers; stopped/superseded streams never fire it.
    var finishStream: AsyncStream<Void> { finishFlag.stream }

    /// Emits a single `Void` once enough audio is queued to start playback (or rendering ended or
    /// the stream stopped — anything that makes further waiting pointless), then completes.
    var readyForPlaybackStream: AsyncStream<Void> { readySignal.stream }

    init(
        request: TrackerStreamRequest,
        effectsSettingsBox: SoundtrackEffectsSettingsBox
    ) throws {
        self.request = request
        self.effectsSettingsBox = effectsSettingsBox
        let module = try ModuleLoader.load(url: request.track.url)
        moduleTitle = module.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let sampleRate = Int(request.sampleRate.rounded())
        format = AVAudioFormat(standardFormatWithSampleRate: request.sampleRate, channels: 2)!
        maxFrameCount = max(1, Int((request.maxDuration * request.sampleRate).rounded()))
        maxQueuedFrameCount = max(16_384, request.streamBufferFrames)
        renderChunkFrameCount = max(1024, min(request.streamRenderChunkFrames, maxQueuedFrameCount))
        let cappedPrerollFrameCount = min(request.streamPrerollFrames, maxQueuedFrameCount)
        playbackStartFrameCount = min(max(1, cappedPrerollFrameCount), maxFrameCount)
        renderer = ModuleRenderer(
            module: module,
            sampleRate: sampleRate,
            options: RenderOptions(
                spatialization: .psychoacoustic3D(.spacious),
                gain: Self.gain(for: request.purpose)
            )
        )
        effectsProcessor = SoundtrackEffectsProcessor(sampleRate: request.sampleRate)
        renderer.prepareSongRendering(tailSeconds: request.tailDuration)
    }

    func startScheduling(on playerNode: AVAudioPlayerNode) {
        condition.lock()
        self.playerNode = playerNode
        let shouldStart: Bool
        if didStartRendering {
            shouldStart = false
        } else {
            didStartRendering = true
            didExitScheduling = false
            shouldStart = true
        }
        condition.unlock()

        guard shouldStart else { return }

        let thread = Thread { [self] in
            scheduleLoop()
        }
        thread.name = "SwiftBuilder Tracker Buffer Scheduler"
        thread.qualityOfService = .default // .userInitiated caused issues
        thread.start()
    }

    func stop(waitUntilSchedulerExits: Bool = true) {
        let deadline = Date(timeIntervalSinceNow: 0.5)
        condition.lock()
        stopRequested = true
        condition.broadcast()
        while waitUntilSchedulerExits && didStartRendering && !didExitScheduling {
            guard condition.wait(until: deadline) else { break }
        }
        condition.unlock()
        // Release any readiness waiter — there is nothing left to wait for.
        readySignal.signal()
    }

    private func scheduleLoop() {
        defer { markSchedulerExited() }

        while true {
            guard waitForSchedulingCapacity() else { return }
            guard let playerNode else { return }

            let remainingFrames = maxFrameCount - renderedFrameCount
            guard remainingFrames > 0 else {
                markRenderComplete()
                return
            }

            let requestedFrames = min(renderChunkFrameCount, remainingFrames)
            let songFrames = renderer.renderSongFrames(frameCount: requestedFrames)
            guard songFrames.buffer.frameCount > 0 else {
                markRenderComplete()
                return
            }

            renderedFrameCount += songFrames.buffer.frameCount
            let processed = effectsProcessor.process(songFrames.buffer, settings: effectsSettingsBox.get())
            guard let audioBuffer = makeAudioBuffer(from: processed) else {
                markRenderComplete()
                return
            }
            guard shouldContinueScheduling() else { return }

            schedule(audioBuffer, on: playerNode)

            if songFrames.isFinished || renderedFrameCount >= maxFrameCount {
                markRenderComplete()
                return
            }
        }
    }

    private func markSchedulerExited() {
        condition.lock()
        didExitScheduling = true
        condition.broadcast()
        condition.unlock()
    }

    private func waitForSchedulingCapacity() -> Bool {
        condition.lock()
        defer { condition.unlock() }

        while !stopRequested && queuedFrameCount > maxQueuedFrameCount - renderChunkFrameCount {
            _ = condition.wait(until: Date(timeIntervalSinceNow: 0.05))
        }
        return !stopRequested
    }

    private func shouldContinueScheduling() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return !stopRequested
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, on playerNode: AVAudioPlayerNode) {
        let frameCount = Int(buffer.frameLength)
        condition.lock()
        queuedFrameCount += frameCount
        let becameReady = queuedFrameCount >= playbackStartFrameCount
        condition.broadcast()
        condition.unlock()
        if becameReady {
            readySignal.signal()
        }

        let completionQueue = completionQueue
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            completionQueue.async { [weak self] in
                self?.bufferDidPlay(frameCount: frameCount)
            }
        }
    }

    private func bufferDidPlay(frameCount: Int) {
        condition.lock()
        queuedFrameCount = max(0, queuedFrameCount - frameCount)
        let shouldFinish = !stopRequested && didRenderFinalBuffer && queuedFrameCount == 0
        condition.broadcast()
        condition.unlock()

        if shouldFinish {
            finishOnce()
        }
    }

    private func markRenderComplete() {
        let shouldFinish: Bool
        condition.lock()
        didRenderFinalBuffer = true
        shouldFinish = !stopRequested && queuedFrameCount == 0
        condition.broadcast()
        condition.unlock()

        // A track shorter than the preroll threshold is as ready as it will ever be.
        readySignal.signal()
        if shouldFinish {
            finishOnce()
        }
    }

    private func makeAudioBuffer(from pcm: PCMBuffer) -> AVAudioPCMBuffer? {
        let frameCount = pcm.frameCount
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
              ) else { return nil }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        if let channels = buffer.floatChannelData, Int(format.channelCount) >= 2 {
            let left = channels[0]
            let right = channels[1]
            for frame in 0..<frameCount {
                let sourceIndex = frame * pcm.channelCount
                left[frame] = pcm.interleavedSamples[sourceIndex]
                right[frame] = pcm.interleavedSamples[sourceIndex + min(1, pcm.channelCount - 1)]
            }
        } else if let interleaved = buffer.audioBufferList.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) {
            for frame in 0..<frameCount {
                let outputIndex = frame * 2
                let sourceIndex = frame * pcm.channelCount
                interleaved[outputIndex] = pcm.interleavedSamples[sourceIndex]
                interleaved[outputIndex + 1] = pcm.interleavedSamples[sourceIndex + min(1, pcm.channelCount - 1)]
            }
        }
        return buffer
    }

    private func finishOnce() {
        condition.lock()
        let shouldFinish: Bool
        if didFinish {
            shouldFinish = false
        } else {
            didFinish = true
            shouldFinish = true
        }
        condition.unlock()

        if shouldFinish {
            finishFlag.markFinished()
        }
    }

    private static func gain(for purpose: SoundtrackPurpose) -> Double {
        switch purpose {
        case .failure:
            0.75
        case .success, .test:
            0.9
        case .startup:
            0.85
        case .stage:
            1.0
        }
    }
}
