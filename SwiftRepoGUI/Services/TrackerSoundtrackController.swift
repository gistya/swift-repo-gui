import AVFoundation
import Combine
import CompositionalInit
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

        Task {
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

nonisolated struct SoundtrackNowPlaying: Equatable, Sendable {
    let title: String
    let artist: String
    let detail: String

    var isEmpty: Bool {
        title.isEmpty && artist.isEmpty
    }

    static let empty = SoundtrackNowPlaying(
        title: "NO TRACK",
        artist: "TRACKER OFFLINE",
        detail: ""
    )
}

nonisolated struct TrackerModuleTrack: Hashable, Sendable {
    let url: URL
    let fileName: String
    let title: String
    let format: String
}

private nonisolated enum SoundtrackPhase: String, Sendable, Equatable {
    case stopped
    case loading
    case playing
    case paused
    case failed
}

private nonisolated enum SoundtrackMachineState: String, StateIdentifying {
    case playback
    case playing
    case notPlaying
    case tubeRack
    case tubeRackOn
    case tubeRackOff
    static var _blank: SoundtrackMachineState { .playback }
}

private nonisolated enum SoundtrackEvent: EventIdentifying {
    case restore(muted: Bool, volume: Double, effects: SoundtrackEffectsSettings)
    case setMuted(Bool)
    case setVolume(Double)
    case setEffects(SoundtrackEffectsSettings)
    case setPurpose(SoundtrackPurpose)
    case requestTrack(TrackerModuleTrack, purpose: SoundtrackPurpose, generation: Int)
    case trackReady(TrackerModuleTrack, moduleTitle: String?, generation: Int)
    case pause
    case resume
    case stop
    case fail(String)
    case finish

    static var _blank: SoundtrackEvent { .stop }
}

private nonisolated struct SoundtrackContext: Sendable, Equatable {
    var phase: SoundtrackPhase = .stopped
    var isMuted = false
    var volume: Double = Double(SwiftBuilderStyle.current.sound.masterVolume)
    var effectsSettings: SoundtrackEffectsSettings = .default
    var currentTrack: TrackerModuleTrack?
    var nowPlaying: SoundtrackNowPlaying = .empty
    var activePurpose: SoundtrackPurpose = .startup
    var generation = 0
    var lastError: String?

    var isPaused: Bool { phase == .paused }
}

private struct SoundtrackMachine: StateMachine {
    typealias Context = SoundtrackContext
    typealias StateID = SoundtrackMachineState
    typealias EventID = SoundtrackEvent

    var context: SoundtrackContext { .init() }
    var isParallel: Bool { true }

    var machine: some XStateMachine {
        XState(.playback) {
            XState(.notPlaying) {
                for transition in Self.notPlayingTransitions() {
                    transition
                }
            }
            .initial()

            XState(.playing) {
                for transition in Self.playingTransitions() {
                    transition
                }
            }
        }

        XState(.tubeRack) {
            XState(.tubeRackOff) {
                for transition in Self.tubeRackTransitions() {
                    transition
                }
            }
            .initial()

            XState(.tubeRackOn) {
                for transition in Self.tubeRackTransitions() {
                    transition
                }
            }
        }
    }

    private static func notPlayingTransitions() -> [XTransition<SoundtrackContext, SoundtrackEvent, SoundtrackMachineState>] {
        [
            XTransition(on: SoundtrackEvent.restore, to: .notPlaying)
                .action { args, _ in Self.applyRestore(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.setMuted, to: .notPlaying)
                .action { args, _ in Self.applyMuted(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.setVolume, to: .notPlaying)
                .action { args, _ in Self.applyVolume(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.setPurpose, to: .notPlaying)
                .action { args, _ in Self.applyPurpose(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.requestTrack, to: .notPlaying)
                .action { args, _ in Self.applyTrackRequest(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.trackReady, to: .playing)
                .when { ctx, event in Self.canPlayTrackReady(event, context: ctx) }
                .action { args, _ in Self.applyTrackReady(args.event, to: args.context, phase: .playing) },
            XTransition(on: SoundtrackEvent.trackReady, to: .notPlaying)
                .action { args, _ in Self.applyTrackReady(args.event, to: args.context, phase: .stopped) },
            XTransition(on: SoundtrackEvent.resume, to: .playing)
                .when { $0.currentTrack != nil && !$0.isMuted }
                .action { ctx in
                    var ctx = ctx
                    ctx.phase = .playing
                    return ctx
                },
            XTransition(on: SoundtrackEvent.resume, to: .notPlaying)
                .action { args, _ in Self.applyResume(args.context) },
            XTransition(on: SoundtrackEvent.stop, to: .notPlaying)
                .action { args, _ in Self.applyStop(args.context) },
            XTransition(on: SoundtrackEvent.fail, to: .notPlaying)
                .action { args, _ in Self.applyFailure(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.finish, to: .notPlaying)
                .action { args, _ in Self.applyFinish(args.context) },
        ]
    }

    private static func playingTransitions() -> [XTransition<SoundtrackContext, SoundtrackEvent, SoundtrackMachineState>] {
        [
            XTransition(on: SoundtrackEvent.restore, to: .notPlaying)
                .when { _, event in Self.restoreMutes(event) }
                .action { args, _ in Self.applyRestore(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.restore, to: .playing)
                .action { args, _ in Self.applyRestore(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.setMuted, to: .notPlaying)
                .when { _, event in Self.muteEventTurnsOff(event) }
                .action { args, _ in Self.applyMuted(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.setMuted, to: .playing)
                .action { args, _ in Self.applyMuted(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.setVolume, to: .playing)
                .action { args, _ in Self.applyVolume(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.setPurpose, to: .playing)
                .action { args, _ in Self.applyPurpose(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.requestTrack, to: .notPlaying)
                .action { args, _ in Self.applyTrackRequest(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.pause, to: .notPlaying)
                .when { $0.currentTrack != nil && !$0.isMuted }
                .action { ctx in
                    var ctx = ctx
                    ctx.phase = .paused
                    return ctx
                },
            XTransition(on: SoundtrackEvent.stop, to: .notPlaying)
                .action { args, _ in Self.applyStop(args.context) },
            XTransition(on: SoundtrackEvent.fail, to: .notPlaying)
                .action { args, _ in Self.applyFailure(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.finish, to: .notPlaying)
                .action { args, _ in Self.applyFinish(args.context) },
        ]
    }

    private static func tubeRackTransitions() -> [XTransition<SoundtrackContext, SoundtrackEvent, SoundtrackMachineState>] {
        [
            XTransition(on: SoundtrackEvent.restore, to: .tubeRackOn)
                .when { _, event in Self.restoreEffectsEnabled(event) },
            XTransition(on: SoundtrackEvent.restore, to: .tubeRackOff),
            XTransition(on: SoundtrackEvent.setEffects, to: .tubeRackOn)
                .when { _, event in Self.effectsEnabled(event) }
                .action { args, _ in Self.applyEffects(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.setEffects, to: .tubeRackOff)
                .action { args, _ in Self.applyEffects(args.event, to: args.context) },
        ]
    }

    private static func applyRestore(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        if case let .restore(muted, volume, effects)? = event {
            ctx.isMuted = muted
            ctx.volume = min(1, max(0, volume))
            ctx.effectsSettings = effects.normalized()
            if muted {
                ctx.phase = .stopped
                ctx.currentTrack = nil
                ctx.nowPlaying = .empty
            }
        }
        return ctx
    }

    private static func applyMuted(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        if case let .setMuted(muted)? = event {
            ctx.isMuted = muted
            ctx.lastError = nil
            if muted {
                ctx.phase = .stopped
                ctx.currentTrack = nil
                ctx.nowPlaying = .empty
            }
        }
        return ctx
    }

    private static func applyVolume(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        if case let .setVolume(volume)? = event {
            ctx.volume = min(1, max(0, volume))
        }
        return ctx
    }

    private static func applyEffects(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        if case let .setEffects(settings)? = event {
            ctx.effectsSettings = settings.normalized()
        }
        return ctx
    }

    private static func applyPurpose(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        if case let .setPurpose(purpose)? = event {
            ctx.activePurpose = purpose
        }
        return ctx
    }

    private static func applyTrackRequest(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        if case let .requestTrack(track, purpose, generation)? = event {
            ctx.phase = .loading
            ctx.currentTrack = track
            ctx.nowPlaying = track.nowPlaying(moduleTitle: nil)
            ctx.activePurpose = purpose
            ctx.generation = generation
            ctx.lastError = nil
        }
        return ctx
    }

    private static func applyTrackReady(
        _ event: SoundtrackEvent?,
        to context: SoundtrackContext,
        phase: SoundtrackPhase
    ) -> SoundtrackContext {
        var ctx = context
        if case let .trackReady(track, moduleTitle, generation)? = event,
           generation == ctx.generation {
            ctx.currentTrack = track
            ctx.nowPlaying = track.nowPlaying(moduleTitle: moduleTitle)
            ctx.phase = phase
            ctx.lastError = nil
        }
        return ctx
    }

    private static func applyResume(_ context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        guard !ctx.isMuted else { return ctx }
        ctx.phase = ctx.currentTrack == nil ? .stopped : .playing
        return ctx
    }

    private static func applyStop(_ context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        ctx.phase = .stopped
        ctx.currentTrack = nil
        ctx.nowPlaying = .empty
        return ctx
    }

    private static func applyFailure(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        if case let .fail(message)? = event {
            ctx.phase = .failed
            ctx.lastError = message
        }
        return ctx
    }

    private static func applyFinish(_ context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        ctx.phase = .stopped
        return ctx
    }

    private static func canPlayTrackReady(_ event: SoundtrackEvent?, context: SoundtrackContext) -> Bool {
        guard !context.isMuted,
              case let .trackReady(_, _, generation)? = event else { return false }
        return generation == context.generation
    }

    private static func restoreMutes(_ event: SoundtrackEvent?) -> Bool {
        guard case let .restore(muted, _, _)? = event else { return false }
        return muted
    }

    private static func muteEventTurnsOff(_ event: SoundtrackEvent?) -> Bool {
        guard case let .setMuted(muted)? = event else { return false }
        return muted
    }

    private static func restoreEffectsEnabled(_ event: SoundtrackEvent?) -> Bool {
        guard case let .restore(_, _, effects)? = event else { return false }
        return effects.normalized().isEnabled
    }

    private static func effectsEnabled(_ event: SoundtrackEvent?) -> Bool {
        guard case let .setEffects(settings)? = event else { return false }
        return settings.normalized().isEnabled
    }
}

nonisolated enum TrackerModuleLibrary {
    static var supportedExtensions: [String] {
        SwiftBuilderStyle.current.sound.trackerModuleExtensions.map { $0.lowercased() }
    }

    static func discover(in bundle: Bundle = .main) -> [TrackerModuleTrack] {
        var urls = Set<URL>()
        let moduleDirectory = SwiftBuilderStyle.current.sound.trackerModuleDirectory
        let subdirectories: [String?] = [
            moduleDirectory,
            "Resources/\(moduleDirectory)",
            nil
        ]

        for ext in supportedExtensions {
            for subdirectory in subdirectories {
                bundle.urls(forResourcesWithExtension: ext, subdirectory: subdirectory)?.forEach {
                    urls.insert($0.standardizedFileURL)
                }
            }
        }

        if let resourceURL = bundle.resourceURL {
            urls.formUnion(moduleURLs(under: resourceURL))
        }

        urls.formUnion(moduleURLs(under: sourceCheckoutModuleDirectory()))

        return urls
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let fileName = url.lastPathComponent
                let format = url.pathExtension.uppercased()
                return TrackerModuleTrack(
                    url: url,
                    fileName: fileName,
                    title: url.deletingPathExtension().lastPathComponent,
                    format: format
                )
            }
    }

    private static func moduleURLs(under directory: URL) -> Set<URL> {
        guard FileManager.default.fileExists(atPath: directory.path),
              let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }

        var urls = Set<URL>()
        for case let url as URL in enumerator {
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            urls.insert(url.standardizedFileURL)
        }
        return urls
    }

    private static func sourceCheckoutModuleDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/TrackerModules", isDirectory: true)
    }
}

private nonisolated struct TrackerStreamRequest: Sendable {
    let track: TrackerModuleTrack
    let purpose: SoundtrackPurpose
    let sampleRate: Double
    let streamBufferFrames: Int
    let streamPrerollFrames: Int
    let streamRenderChunkFrames: Int
    let maxDuration: Double
    let tailDuration: Double
}

private nonisolated struct PreparedTrackerStream: Sendable {
    let track: TrackerModuleTrack
    let succeeded: Bool
    let moduleTitle: String?
    let errorMessage: String?
}

private actor SoundtrackAudioActor {
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

            if startImmediately {
                stream.waitUntilReadyForPlayback(timeout: 0.35)
                guard await startEngineOrFail() else {
                    return PreparedTrackerStream(
                        track: request.track,
                        succeeded: false,
                        moduleTitle: stream.moduleTitle,
                        errorMessage: lastEngineError ?? "Audio engine unavailable."
                    )
                }
                stream.play()
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
        guard activeStream != nil else { return }
        guard await startEngineOrFail() else { return }
        activeStream?.play()
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
        engine.disconnectNodeOutput(stream.playerNode)
        engine.detach(stream.playerNode)
        activeStream = nil
    }

    private static func localizedErrorMessage(for error: any Error) -> String {
        if let localizedError = error as? any LocalizedError,
           let description = localizedError.errorDescription?.nilIfEmpty {
            return description
        }
        return error.localizedDescription
    }
}

private nonisolated enum SoundtrackAudioPhase: String, Sendable, Equatable {
    case stopped
    case loading
    case ready
    case playing
    case paused
    case failed
}

private nonisolated enum SoundtrackAudioMachineState: String, StateIdentifying {
    case playback
    case playing
    case notPlaying
    case tubeRack
    case tubeRackOn
    case tubeRackOff
    static var _blank: SoundtrackAudioMachineState { .playback }
}

private nonisolated enum SoundtrackAudioEvent: EventIdentifying {
    case requestTrack(TrackerModuleTrack, purpose: SoundtrackPurpose, generation: Int)
    case trackReady(moduleTitle: String?, generation: Int)
    case setVolume(Double)
    case setEffects(SoundtrackEffectsSettings)
    case play
    case pause
    case stop
    case fail(String)

    static var _blank: SoundtrackAudioEvent { .stop }
}

private nonisolated struct SoundtrackAudioContext: Sendable, Equatable {
    var phase: SoundtrackAudioPhase = .stopped
    var currentTrack: TrackerModuleTrack?
    var activePurpose: SoundtrackPurpose = .startup
    var moduleTitle: String?
    var generation = 0
    var volume: Double = Double(SwiftBuilderStyle.current.sound.masterVolume)
    var effectsSettings: SoundtrackEffectsSettings = .default
    var lastError: String?
}

private struct SoundtrackAudioMachine: StateMachine {
    typealias Context = SoundtrackAudioContext
    typealias StateID = SoundtrackAudioMachineState
    typealias EventID = SoundtrackAudioEvent

    var context: SoundtrackAudioContext { .init() }
    var isParallel: Bool { true }

    var machine: some XStateMachine {
        XState(.playback) {
            XState(.notPlaying) {
                for transition in Self.notPlayingTransitions() {
                    transition
                }
            }
            .initial()

            XState(.playing) {
                for transition in Self.playingTransitions() {
                    transition
                }
            }
        }

        XState(.tubeRack) {
            XState(.tubeRackOff) {
                for transition in Self.tubeRackTransitions() {
                    transition
                }
            }
            .initial()

            XState(.tubeRackOn) {
                for transition in Self.tubeRackTransitions() {
                    transition
                }
            }
        }
    }

    private static func notPlayingTransitions() -> [XTransition<SoundtrackAudioContext, SoundtrackAudioEvent, SoundtrackAudioMachineState>] {
        [
            XTransition(on: SoundtrackAudioEvent.requestTrack, to: .notPlaying)
                .action { args, _ in Self.applyTrackRequest(args.event, to: args.context) },
            XTransition(on: SoundtrackAudioEvent.trackReady, to: .notPlaying)
                .action { args, _ in Self.applyTrackReady(args.event, to: args.context) },
            XTransition(on: SoundtrackAudioEvent.setVolume, to: .notPlaying)
                .action { args, _ in Self.applyVolume(args.event, to: args.context) },
            XTransition(on: .play, to: .playing)
                .when { $0.currentTrack != nil }
                .action { ctx in
                    var ctx = ctx
                    ctx.phase = .playing
                    ctx.lastError = nil
                    return ctx
                },
            XTransition(on: .pause, to: .notPlaying)
                .action { ctx in
                    var ctx = ctx
                    ctx.phase = .paused
                    return ctx
                },
            XTransition(on: .stop, to: .notPlaying)
                .action { args, _ in Self.applyStop(args.context) },
            XTransition(on: SoundtrackAudioEvent.fail, to: .notPlaying)
                .action { args, _ in Self.applyFailure(args.event, to: args.context) },
        ]
    }

    private static func playingTransitions() -> [XTransition<SoundtrackAudioContext, SoundtrackAudioEvent, SoundtrackAudioMachineState>] {
        [
            XTransition(on: SoundtrackAudioEvent.requestTrack, to: .notPlaying)
                .action { args, _ in Self.applyTrackRequest(args.event, to: args.context) },
            XTransition(on: SoundtrackAudioEvent.setVolume, to: .playing)
                .action { args, _ in Self.applyVolume(args.event, to: args.context) },
            XTransition(on: .pause, to: .notPlaying)
                .action { ctx in
                    var ctx = ctx
                    ctx.phase = .paused
                    return ctx
                },
            XTransition(on: .stop, to: .notPlaying)
                .action { args, _ in Self.applyStop(args.context) },
            XTransition(on: SoundtrackAudioEvent.fail, to: .notPlaying)
                .action { args, _ in Self.applyFailure(args.event, to: args.context) },
        ]
    }

    private static func tubeRackTransitions() -> [XTransition<SoundtrackAudioContext, SoundtrackAudioEvent, SoundtrackAudioMachineState>] {
        [
            XTransition(on: SoundtrackAudioEvent.setEffects, to: .tubeRackOn)
                .when { _, event in Self.effectsEnabled(event) }
                .action { args, _ in Self.applyEffects(args.event, to: args.context) },
            XTransition(on: SoundtrackAudioEvent.setEffects, to: .tubeRackOff)
                .action { args, _ in Self.applyEffects(args.event, to: args.context) },
        ]
    }

    private static func applyTrackRequest(
        _ event: SoundtrackAudioEvent?,
        to context: SoundtrackAudioContext
    ) -> SoundtrackAudioContext {
        var ctx = context
        guard case let .requestTrack(track, purpose, generation)? = event else { return ctx }
        ctx.phase = .loading
        ctx.currentTrack = track
        ctx.activePurpose = purpose
        ctx.moduleTitle = nil
        ctx.generation = generation
        ctx.lastError = nil
        return ctx
    }

    private static func applyTrackReady(
        _ event: SoundtrackAudioEvent?,
        to context: SoundtrackAudioContext
    ) -> SoundtrackAudioContext {
        var ctx = context
        guard case let .trackReady(moduleTitle, generation)? = event,
              generation == ctx.generation else { return ctx }
        ctx.phase = .ready
        ctx.moduleTitle = moduleTitle
        ctx.lastError = nil
        return ctx
    }

    private static func applyVolume(
        _ event: SoundtrackAudioEvent?,
        to context: SoundtrackAudioContext
    ) -> SoundtrackAudioContext {
        var ctx = context
        if case let .setVolume(volume)? = event {
            ctx.volume = min(1, max(0, volume))
        }
        return ctx
    }

    private static func applyEffects(
        _ event: SoundtrackAudioEvent?,
        to context: SoundtrackAudioContext
    ) -> SoundtrackAudioContext {
        var ctx = context
        if case let .setEffects(settings)? = event {
            ctx.effectsSettings = settings.normalized()
        }
        return ctx
    }

    private static func applyStop(_ context: SoundtrackAudioContext) -> SoundtrackAudioContext {
        var ctx = context
        ctx.phase = .stopped
        ctx.currentTrack = nil
        ctx.moduleTitle = nil
        return ctx
    }

    private static func applyFailure(
        _ event: SoundtrackAudioEvent?,
        to context: SoundtrackAudioContext
    ) -> SoundtrackAudioContext {
        var ctx = context
        if case let .fail(message)? = event {
            ctx.phase = .failed
            ctx.lastError = message
        }
        return ctx
    }

    private static func effectsEnabled(_ event: SoundtrackAudioEvent?) -> Bool {
        guard case let .setEffects(settings)? = event else { return false }
        return settings.normalized().isEnabled
    }
}

private nonisolated enum SoundtrackPurpose: Sendable, Equatable, Hashable {
    case startup
    case stage(BuildStage)
    case success
    case failure
    case test
}

private nonisolated final class SoundtrackEffectsSettingsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: SoundtrackEffectsSettings

    init(_ settings: SoundtrackEffectsSettings) {
        storage = settings.normalized()
    }

    func get() -> SoundtrackEffectsSettings {
        lock.withLock { storage }
    }

    func set(_ settings: SoundtrackEffectsSettings) {
        lock.withLock {
            storage = settings.normalized()
        }
    }
}

private nonisolated final class TrackerAudioStream: @unchecked Sendable {
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

    func play() {
        guard !isFinished else { return }
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    func pause() {
        if playerNode.isPlaying {
            playerNode.pause()
        }
    }

    func stop() {
        playerNode.stop()
        core.stop()
    }

    deinit {
        core.stop()
    }
}

private nonisolated final class SoundtrackStreamFinishFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    var isFinished: Bool {
        lock.withLock { finished }
    }

    func markFinished() {
        lock.withLock {
            finished = true
        }
    }
}

private nonisolated final class TrackerAudioStreamCore: @unchecked Sendable {
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
    private let condition = NSCondition()
    private weak var playerNode: AVAudioPlayerNode?
    private var renderedFrameCount = 0
    private var queuedFrameCount = 0
    private var didRenderFinalBuffer = false
    private var didFinish = false
    private var didStartRendering = false
    private var stopRequested = false
    var isFinished: Bool { finishFlag.isFinished }

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
        maxQueuedFrameCount = max(4_096, request.streamBufferFrames)
        renderChunkFrameCount = max(512, min(request.streamRenderChunkFrames, maxQueuedFrameCount))
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
            shouldStart = true
        }
        condition.unlock()

        guard shouldStart else { return }

        let thread = Thread { [self] in
            scheduleLoop()
        }
        thread.name = "SwiftBuilder Tracker Buffer Scheduler"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func waitUntilReadyForPlayback(timeout: TimeInterval) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        condition.lock()
        defer { condition.unlock() }

        while !stopRequested &&
            !didFinish &&
            !didRenderFinalBuffer &&
            queuedFrameCount < playbackStartFrameCount {
            guard condition.wait(until: deadline) else { break }
        }
    }

    func stop() {
        condition.lock()
        stopRequested = true
        condition.broadcast()
        condition.unlock()
    }

    private func scheduleLoop() {
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

            schedule(audioBuffer, on: playerNode)

            if songFrames.isFinished || renderedFrameCount >= maxFrameCount {
                markRenderComplete()
                return
            }
        }
    }

    private func waitForSchedulingCapacity() -> Bool {
        condition.lock()
        defer { condition.unlock() }

        while !stopRequested && queuedFrameCount > maxQueuedFrameCount - renderChunkFrameCount {
            _ = condition.wait(until: Date(timeIntervalSinceNow: 0.05))
        }
        return !stopRequested
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, on playerNode: AVAudioPlayerNode) {
        let frameCount = Int(buffer.frameLength)
        condition.lock()
        queuedFrameCount += frameCount
        condition.broadcast()
        condition.unlock()

        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.bufferDidPlay(frameCount: frameCount)
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


extension TrackerModuleTrack {
    nonisolated func nowPlaying(moduleTitle: String?) -> SoundtrackNowPlaying {
        let parts = Self.displayParts(from: title)
        return SoundtrackNowPlaying(
            title: moduleTitle?.nilIfEmpty ?? parts.title,
            artist: parts.artist,
            detail: format
        )
    }

    nonisolated static func displayParts(from rawTitle: String) -> (title: String, artist: String) {
        let separators = ["_-_", " - ", " – "]
        for separator in separators {
            if let range = rawTitle.range(of: separator) {
                let artist = cleanedDisplayText(String(rawTitle[..<range.lowerBound]))
                let title = cleanedDisplayText(String(rawTitle[range.upperBound...]))
                return (
                    title: title.nilIfEmpty ?? cleanedDisplayText(rawTitle),
                    artist: artist.nilIfEmpty ?? "TRACKER MODULE"
                )
            }
        }
        return (
            title: cleanedDisplayText(rawTitle),
            artist: "TRACKER MODULE"
        )
    }

    nonisolated static func cleanedDisplayText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .uppercased()
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
