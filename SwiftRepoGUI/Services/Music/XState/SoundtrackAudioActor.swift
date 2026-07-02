import AVFoundation
import SwiftXState

actor SoundtrackAudioActor {
    private let format: AVAudioFormat
    private let engine = AVAudioEngine()
    private let effectsSettingsBox: SoundtrackEffectsSettingsBox
    private let audioMachine: MachineActor<SoundtrackAudioMachine>
    private let initialVolume: Double
    private let initialEffectsSettings: SoundtrackEffectsSettings

    private var activeStream: TrackerAudioStream?
    private var activeGeneration = 0
    private var audioAvailable = true
    private var didStartMachine = false
    private var lastEngineError: String?

    init(
        style: SoundPalette,
        volume: Float,
        effectsSettings: SoundtrackEffectsSettings,
        inspect: (@Sendable (InspectionEvent) -> Void)? = nil
    ) {
        format = AVAudioFormat(standardFormatWithSampleRate: style.sampleRate, channels: 2)!
        let normalizedEffects = effectsSettings.normalized()
        effectsSettingsBox = SoundtrackEffectsSettingsBox(normalizedEffects)
        initialVolume = Double(volume)
        initialEffectsSettings = normalizedEffects
        audioMachine = createActor(
            SoundtrackAudioMachine(),
            id: "swiftbuilder.soundtrack.audio",
            options: ActorOptions(
                systemId: "swiftbuilder.soundtrack.audio",
                snapshotMicrosteps: false
            ),
            inspect: inspect
        )
        engine.mainMixerNode.outputVolume = volume
        engine.prepare()
    }

    func setVolume(_ volume: Float) async {
        await ensureMachineStarted()
        let clamped = min(1, max(0, volume))
        engine.mainMixerNode.outputVolume = clamped
        await audioMachine.send(.setVolume(Double(clamped)))
    }

    func setEffectsSettings(_ settings: SoundtrackEffectsSettings) async {
        await ensureMachineStarted()
        let normalized = settings.normalized()
        effectsSettingsBox.set(normalized)
        await audioMachine.send(.setEffects(normalized))
    }

    func play(
        request: TrackerStreamRequest,
        generation: Int,
        startImmediately: Bool
    ) async -> PreparedTrackerStream {
        await ensureMachineStarted()
        await audioMachine.send(.requestTrack(request.track, purpose: request.purpose, generation: generation))

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
            install(stream)
            await audioMachine.send(.trackReady(moduleTitle: stream.moduleTitle, generation: generation))
            guard isCurrent(stream, generation: generation) else {
                return supersededStream(for: request, stream: stream)
            }

            if startImmediately {
                stream.waitUntilReadyForPlayback(timeout: 0.35)
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
                    let message = "Audio stream is no longer connected to the engine."
                    await audioMachine.send(.fail(message))
                    return PreparedTrackerStream(
                        track: request.track,
                        succeeded: false,
                        moduleTitle: stream.moduleTitle,
                        errorMessage: message
                    )
                }
                await audioMachine.send(.play)
            }

            return PreparedTrackerStream(
                track: request.track,
                succeeded: true,
                moduleTitle: stream.moduleTitle,
                errorMessage: nil
            )
        } catch {
            let message = Self.localizedErrorMessage(for: error)
            await audioMachine.send(.fail(message))
            return PreparedTrackerStream(
                track: request.track,
                succeeded: false,
                moduleTitle: nil,
                errorMessage: message
            )
        }
    }

    func pause() async {
        await ensureMachineStarted()
        activeStream?.pause()
        if engine.isRunning {
            engine.pause()
        }
        await audioMachine.send(.pause)
    }

    func resume() async {
        await ensureMachineStarted()
        guard let stream = activeStream else { return }
        guard await startEngineOrFail() else { return }
        guard isCurrent(stream, generation: activeGeneration) else { return }
        guard stream.play() else {
            await audioMachine.send(.fail("Audio stream is no longer connected to the engine."))
            return
        }
        await audioMachine.send(.play)
    }

    func stop() async {
        await ensureMachineStarted()
        if engine.isRunning {
            engine.pause()
        }
        stopActiveStream()
        activeGeneration += 1
        await audioMachine.send(.stop)
    }

    func isFinished(generation: Int) async -> Bool {
        generation == activeGeneration && activeStream?.isFinished == true
    }

    private func ensureMachineStarted() async {
        guard !didStartMachine else { return }
        await audioMachine.start()
        await audioMachine.send(.setVolume(initialVolume))
        await audioMachine.send(.setEffects(initialEffectsSettings))
        didStartMachine = true
    }

    private func startEngineOrFail() async -> Bool {
        guard audioAvailable else {
            await audioMachine.send(.fail(lastEngineError ?? "Audio engine unavailable."))
            return false
        }
        guard !engine.isRunning else { return true }

        do {
            try engine.start()
            lastEngineError = nil
            return true
        } catch {
            let message = Self.localizedErrorMessage(for: error)
            audioAvailable = false
            lastEngineError = message
            await audioMachine.send(.fail(message))
            return false
        }
    }

    private func install(_ stream: TrackerAudioStream) {
        activeStream = stream
        engine.attach(stream.playerNode)
        engine.connect(stream.playerNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        stream.startScheduling()
    }

    private func stopActiveStream() {
        guard let stream = activeStream else { return }
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
