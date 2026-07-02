import AVFoundation

actor SoundtrackAudioActor {
    nonisolated private let finishedGenerationBroadcaster = AsyncEventBroadcaster<Int>()

    nonisolated var finishedGenerations: AsyncStream<Int> {
        finishedGenerationBroadcaster.stream(bufferingPolicy: .bufferingNewest(16))
    }

    private let format: AVAudioFormat
    private let engine = AVAudioEngine()
    private let effectsSettingsBox: SoundtrackEffectsSettingsBox

    private var activeStream: TrackerAudioStream?
    private var activeGeneration = 0
    private var audioAvailable = true
    private var lastEngineError: String?
    private var finishTask: Task<Void, Never>?

    init(
        style: SoundPalette,
        volume: Float,
        effectsSettings: SoundtrackEffectsSettings
    ) {
        format = AVAudioFormat(standardFormatWithSampleRate: style.sampleRate, channels: 2)!
        effectsSettingsBox = SoundtrackEffectsSettingsBox(effectsSettings.normalized())
        engine.mainMixerNode.outputVolume = volume
        engine.prepare()
    }

    func setVolume(_ volume: Double) async {
        engine.mainMixerNode.outputVolume = Float(min(1, max(0, volume)))
    }

    func setEffectsSettings(_ settings: SoundtrackEffectsSettings) async {
        effectsSettingsBox.set(settings.normalized())
    }

    func play(
        request: TrackerStreamRequest,
        generation: Int,
        startImmediately: Bool
    ) async -> PreparedTrackerStream {
        if engine.isRunning {
            engine.pause()
        }
        stopActiveStream()
        activeGeneration = generation

        do {
            let stream = try TrackerAudioStream(
                request: request,
                effectsSettingsBox: effectsSettingsBox
            )
            install(stream, generation: generation)
            guard isCurrent(stream, generation: generation) else {
                return supersededStream(for: request, stream: stream)
            }

            if startImmediately {
                await stream.awaitReadyForPlayback(timeout: 0.35)
                guard isCurrent(stream, generation: generation) else {
                    return supersededStream(for: request, stream: stream)
                }
                guard await startEngineOrFail() else {
                    return PreparedTrackerStream(
                        track: request.track,
                        succeeded: false,
                        moduleTitle: stream.moduleTitle,
                        errorMessage: lastEngineError ?? "Audio engine unavailable."
                    )
                }
                guard isCurrent(stream, generation: generation) else {
                    return supersededStream(for: request, stream: stream)
                }
                guard stream.play() else {
                    return PreparedTrackerStream(
                        track: request.track,
                        succeeded: false,
                        moduleTitle: stream.moduleTitle,
                        errorMessage: "Audio stream is no longer connected to the engine."
                    )
                }
            }

            return PreparedTrackerStream(
                track: request.track,
                succeeded: true,
                moduleTitle: stream.moduleTitle,
                errorMessage: nil
            )
        } catch {
            return PreparedTrackerStream(
                track: request.track,
                succeeded: false,
                moduleTitle: nil,
                errorMessage: Self.localizedErrorMessage(for: error)
            )
        }
    }

    func pause() async -> String? {
        activeStream?.pause()
        if engine.isRunning {
            engine.pause()
        }
        return nil
    }

    func resume() async -> String? {
        guard let stream = activeStream else {
            return "No tracker stream is ready to resume."
        }
        guard await startEngineOrFail() else {
            return lastEngineError ?? "Audio engine unavailable."
        }
        guard isCurrent(stream, generation: activeGeneration) else {
            return "Audio stream was replaced before playback resumed."
        }
        guard stream.play() else {
            return "Audio stream is no longer connected to the engine."
        }
        return nil
    }

    func stop() async {
        if engine.isRunning {
            engine.pause()
        }
        stopActiveStream()
        activeGeneration += 1
    }

    private func streamDidFinish(_ stream: TrackerAudioStream, generation: Int) async {
        guard activeStream === stream, generation == activeGeneration else { return }
        if engine.isRunning {
            engine.pause()
        }
        stream.stop()
        if stream.isConnected(to: engine) {
            engine.disconnectNodeOutput(stream.playerNode)
            engine.detach(stream.playerNode)
        }
        activeStream = nil
        finishTask = nil
        finishedGenerationBroadcaster.yield { generation }
    }

    private func startEngineOrFail() async -> Bool {
        guard audioAvailable else { return false }
        guard !engine.isRunning else { return true }

        do {
            try engine.start()
            lastEngineError = nil
            return true
        } catch {
            let message = Self.localizedErrorMessage(for: error)
            audioAvailable = false
            lastEngineError = message
            return false
        }
    }

    private func install(_ stream: TrackerAudioStream, generation: Int) {
        activeStream = stream
        engine.attach(stream.playerNode)
        engine.connect(stream.playerNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        let finishStream = stream.finishStream
        finishTask = Task { [weak self, stream] in
            for await _ in finishStream {
                await self?.streamDidFinish(stream, generation: generation)
                return
            }
        }
        stream.startScheduling()
    }

    private func stopActiveStream() {
        guard let stream = activeStream else { return }
        finishTask?.cancel()
        finishTask = nil
        stream.stop()
        if stream.isConnected(to: engine) {
            engine.disconnectNodeOutput(stream.playerNode)
            engine.detach(stream.playerNode)
        }
        activeStream = nil
    }

    private func isCurrent(_ stream: TrackerAudioStream, generation: Int) -> Bool {
        guard let activeStream else { return false }
        return generation == activeGeneration && activeStream === stream
    }

    private func supersededStream(
        for request: TrackerStreamRequest,
        stream: TrackerAudioStream
    ) -> PreparedTrackerStream {
        PreparedTrackerStream(
            track: request.track,
            succeeded: false,
            moduleTitle: stream.moduleTitle,
            errorMessage: "Audio stream was replaced before playback started."
        )
    }

    private static func localizedErrorMessage(for error: any Error) -> String {
        if let localizedError = error as? any LocalizedError,
           let description = localizedError.errorDescription?.nilIfEmpty {
            return description
        }
        return error.localizedDescription
    }
}
