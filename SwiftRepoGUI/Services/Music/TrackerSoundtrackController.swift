import AVFoundation
import Combine
import Foundation
import Ox0badf00d
import SwiftXState
import SwiftXStateSwiftUI

@MainActor
final class TrackerSoundtrackController: ObservableObject {
    @Published private(set) var isMuted = false
    @Published private(set) var isPaused = false
    @Published private(set) var nowPlaying: SoundtrackNowPlaying = .empty
    @Published private(set) var volume: Double = Double(SwiftBuilderStyle.current.sound.masterVolume)
    @Published private(set) var effectsSettings: SoundtrackEffectsSettings = .default
    @Published private(set) var lastError: String?

    private static let volumeDefaultsKey = "SwiftBuilder.soundtrackVolume"

    private let stateStore: MainStore
    private let soundtrackMachine: MachineStore<SoundtrackMachine>
    private let audioActor: SoundtrackAudioActor
    private let soundStyle: SoundPalette
    private let defaults: UserDefaults
    private var renderGeneration = 0
    private var currentStage: BuildStage = .off
    private var currentTrack: TrackerModuleTrack?
    private var wasRunning = false
    private var startupPlayed = false
    private var lastContext = BuildOperationsContext()
    private var activePurpose: SoundtrackPurpose = .startup
    private var finishPollTask: Task<Void, Never>?
    private let tracks: [TrackerModuleTrack]

    init(
        defaults: UserDefaults = .standard,
        inspect: (@Sendable (InspectionEvent) -> Void)? = nil
    ) {
        self.defaults = defaults
        let store = MainStore()
        stateStore = store
        let machine = SoundtrackMachine()
        let actor = createActor(
            machine,
            id: "swiftbuilder.soundtrack.ui",
            options: ActorOptions(systemId: "swiftbuilder.soundtrack.ui"),
            inspect: inspect
        )
        soundtrackMachine = store.track(MachineStore(actor: actor, initialContext: machine.context))
        let style = SwiftBuilderStyle.current.sound
        soundStyle = style
        tracks = TrackerModuleLibrary.discover()
        let resolvedVolume: Double
        if let savedVolume = defaults.object(forKey: Self.volumeDefaultsKey) as? Double {
            resolvedVolume = Self.clampedVolume(savedVolume)
        } else {
            resolvedVolume = Self.clampedVolume(Double(style.masterVolume))
        }
        volume = resolvedVolume
        let loadedEffects = SoundtrackEffectsSettingsStore.load(from: defaults)
        effectsSettings = loadedEffects
        audioActor = SoundtrackAudioActor(
            style: style,
            volume: Float(resolvedVolume),
            effectsSettings: loadedEffects,
            inspect: inspect
        )

        send(.restore(muted: isMuted, volume: resolvedVolume, effects: loadedEffects))
    }

    func start() {
        guard !startupPlayed, !isMuted else { return }
        startupPlayed = true
        playRandomTrack(for: .startup)
    }

    func setMuted(_ muted: Bool) {
        guard isMuted != muted else { return }
        send(.setMuted(muted))
        if muted {
            stopAll()
        } else {
            if lastContext.isRunning {
                currentStage = .off
                update(for: lastContext, forceStageRefresh: true)
            } else {
                startupPlayed = true
                playRandomTrack(for: .startup)
            }
        }
    }

    func setVolume(_ newVolume: Double) {
        let clamped = Self.clampedVolume(newVolume)
        send(.setVolume(clamped))
        defaults.set(clamped, forKey: Self.volumeDefaultsKey)
        Task {
            await audioActor.setVolume(Float(clamped))
        }
    }

    func setEffectsSettings(_ newSettings: SoundtrackEffectsSettings) {
        let normalized = newSettings.normalized()
        send(.setEffects(normalized))
        SoundtrackEffectsSettingsStore.save(normalized, to: defaults)
        Task {
            await audioActor.setEffectsSettings(normalized)
        }
    }

    func resetEffectsSettings() {
        setEffectsSettings(.default)
    }

    func update(for context: BuildOperationsContext) {
        update(for: context, forceStageRefresh: false)
    }

    func playTestCue() {
        guard !isMuted else { return }
        playRandomTrack(for: .test)
    }

    func togglePause() {
        guard !isMuted else { return }
        if isPaused {
            resume()
        } else {
            pause()
        }
    }

    func playNextTrack() {
        guard !isMuted else { return }
        playTrack(offset: 1)
    }

    func playPreviousTrack() {
        guard !isMuted else { return }
        playTrack(offset: -1)
    }

    private func update(for context: BuildOperationsContext, forceStageRefresh: Bool) {
        lastContext = context
        let stage = BuildStage.stage(for: context)

        if isMuted {
            wasRunning = context.isRunning
            currentStage = stage
            return
        }

        if isPaused {
            wasRunning = context.isRunning
            currentStage = stage
            if stage != .off {
                send(.setPurpose(.stage(stage)))
            }
            return
        }

        if context.isRunning, !wasRunning {
            currentStage = stage
            wasRunning = context.isRunning
            playRandomTrack(for: .stage(stage))
            return
        }

        if stage == .failed, currentStage != .failed {
            currentStage = stage
            wasRunning = context.isRunning
            playRandomTrack(for: .failure)
            return
        }

        if !context.isRunning, wasRunning, context.lastExitCode == 0 {
            currentStage = stage
            wasRunning = context.isRunning
            playRandomTrack(for: .success)
            return
        }

        wasRunning = context.isRunning
        guard forceStageRefresh || stage != currentStage else { return }
        currentStage = stage
        if stage != .off {
            playRandomTrack(for: .stage(stage))
        }
    }

    private func pause() {
        guard currentTrack != nil else { return }
        send(.pause)
        Task {
            await audioActor.pause()
        }
    }

    private func resume() {
        guard currentTrack != nil else {
            send(.resume)
            playRandomTrack(for: activePurpose)
            return
        }
        send(.resume)
        Task {
            await audioActor.resume()
        }
    }

    private func stopAll() {
        renderGeneration += 1
        stopFinishPolling()
        send(.stop)
        Task {
            await audioActor.stop()
        }
    }

    private func playRandomTrack(for purpose: SoundtrackPurpose) {
        guard let track = randomTrack() else {
            send(.fail("No tracker modules were found in the app bundle."))
            return
        }
        play(track, for: purpose)
    }

    private func playTrack(offset: Int) {
        guard let track = track(offsetBy: offset) else {
            send(.fail("No tracker modules were found in the app bundle."))
            return
        }
        play(track, for: activePurpose)
    }

    private func play(_ track: TrackerModuleTrack, for purpose: SoundtrackPurpose) {
        renderGeneration += 1
        let generation = renderGeneration
        stopFinishPolling()
        send(.requestTrack(track, purpose: purpose, generation: generation))
        let request = TrackerStreamRequest(
            track: track,
            purpose: purpose,
            sampleRate: soundStyle.sampleRate,
            streamBufferFrames: soundStyle.streamBufferFrames,
            streamPrerollFrames: soundStyle.streamPrerollFrames,
            streamRenderChunkFrames: soundStyle.streamRenderChunkFrames,
            maxDuration: soundStyle.maxRenderedTrackDuration,
            tailDuration: soundStyle.trackEndTailDuration
        )
        let shouldStart = !isPaused && !isMuted
        let audioActor = audioActor

        Task(priority: .medium) {
            let prepared = await audioActor.play(
                request: request,
                generation: generation,
                startImmediately: shouldStart
            )
            await MainActor.run { [weak self] in
                self?.play(prepared, generation: generation)
            }
        }
    }

    private func play(_ prepared: PreparedTrackerStream, generation: Int) {
        guard generation == renderGeneration, !isMuted else { return }
        guard prepared.succeeded else {
            send(.fail("Could not stream \(prepared.track.fileName): \(prepared.errorMessage ?? "Unknown error")"))
            return
        }
        send(.trackReady(prepared.track, moduleTitle: prepared.moduleTitle, generation: generation))
        startFinishPolling(generation: generation)
    }

    private func startFinishPolling(generation: Int) {
        stopFinishPolling()
        finishPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else { return }
                guard await self.audioActor.isFinished(generation: generation) else { continue }
                self.finishPollTask = nil
                self.trackFinished(generation: generation)
                return
            }
        }
    }

    private func stopFinishPolling() {
        finishPollTask?.cancel()
        finishPollTask = nil
    }

    private func randomTrack() -> TrackerModuleTrack? {
        guard !tracks.isEmpty else { return nil }
        let candidates = tracks.count > 1 ? tracks.filter { $0 != currentTrack } : tracks
        return candidates.randomElement() ?? tracks.randomElement()
    }

    private func track(offsetBy offset: Int) -> TrackerModuleTrack? {
        guard !tracks.isEmpty else { return nil }
        guard let currentTrack, let currentIndex = tracks.firstIndex(of: currentTrack) else {
            return offset >= 0 ? tracks.first : tracks.last
        }
        let nextIndex = (currentIndex + offset + tracks.count) % tracks.count
        return tracks[nextIndex]
    }

    private func trackFinished(generation: Int) {
        guard generation == renderGeneration, !isMuted, !isPaused else { return }
        send(.finish)
        playRandomTrack(for: activePurpose)
    }

    private static func clampedVolume(_ volume: Double) -> Double {
        min(1, max(0, volume))
    }

    private func send(_ event: SoundtrackEvent) {
        soundtrackMachine.send(event)
        syncFromMachine()
    }

    private func syncFromMachine() {
        let context = soundtrackMachine.context
        isMuted = context.isMuted
        isPaused = context.isPaused
        nowPlaying = context.nowPlaying
        volume = context.volume
        effectsSettings = context.effectsSettings
        lastError = context.lastError
        currentTrack = context.currentTrack
        activePurpose = context.activePurpose
    }
}
