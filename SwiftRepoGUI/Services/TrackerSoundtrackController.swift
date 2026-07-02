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
    private let soundStyle: SoundPalette
    private let defaults: UserDefaults
    private let sampleRate: Double
    private let format: AVAudioFormat
    private let engine = AVAudioEngine()
    private let prepareQueue = DispatchQueue(label: "SwiftBuilder.Soundtrack.Prepare", qos: .userInitiated)
    private let effectsSettingsBox = SoundtrackEffectsSettingsBox(.default)
    private var renderGeneration = 0
    private var currentStage: BuildStage = .off
    private var currentTrack: TrackerModuleTrack?
    private var wasRunning = false
    private var audioAvailable = true
    private var startupPlayed = false
    private var lastContext = BuildOperationsContext()
    private var activePurpose: SoundtrackPurpose = .startup
    private var activeStream: TrackerAudioStream?
    private var finishPollTask: Task<Void, Never>?
    private let tracks: [TrackerModuleTrack]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let store = MainStore()
        stateStore = store
        soundtrackMachine = store.track(SoundtrackMachine())
        let style = SwiftBuilderStyle.current.sound
        soundStyle = style
        sampleRate = style.sampleRate
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        tracks = TrackerModuleLibrary.discover()
        if let savedVolume = defaults.object(forKey: Self.volumeDefaultsKey) as? Double {
            volume = Self.clampedVolume(savedVolume)
        } else {
            volume = Self.clampedVolume(Double(style.masterVolume))
        }
        effectsSettings = SoundtrackEffectsSettingsStore.load(from: defaults)
        effectsSettingsBox.set(effectsSettings)

        engine.mainMixerNode.outputVolume = Float(volume)
        engine.prepare()

        send(.restore(muted: isMuted, volume: volume, effects: effectsSettings))
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
            audioAvailable = true
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
        engine.mainMixerNode.outputVolume = Float(clamped)
    }

    func setEffectsSettings(_ newSettings: SoundtrackEffectsSettings) {
        let normalized = newSettings.normalized()
        effectsSettingsBox.set(normalized)
        send(.setEffects(normalized))
        SoundtrackEffectsSettingsStore.save(normalized, to: defaults)
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
        activeStream?.pause()
    }

    private func resume() {
        guard currentTrack != nil else {
            send(.resume)
            playRandomTrack(for: activePurpose)
            return
        }
        guard ensureEngine() else { return }
        activeStream?.play()
        send(.resume)
    }

    private func stopAll() {
        renderGeneration += 1
        if engine.isRunning {
            engine.pause()
        }
        detachActiveStream()
        send(.stop)
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
        send(.requestTrack(track, purpose: purpose, generation: generation))
        let request = TrackerStreamRequest(
            track: track,
            purpose: purpose,
            sampleRate: sampleRate,
            streamBufferFrames: soundStyle.streamBufferFrames,
            streamPrerollFrames: soundStyle.streamPrerollFrames,
            streamRenderChunkFrames: soundStyle.streamRenderChunkFrames,
            maxDuration: soundStyle.maxRenderedTrackDuration,
            tailDuration: soundStyle.trackEndTailDuration
        )
        let effectsSettingsBox = effectsSettingsBox

        prepareQueue.async { [weak self] in
            let prepared = Self.prepareStream(
                for: request,
                effectsSettingsBox: effectsSettingsBox
            )
            DispatchQueue.main.async { [weak self] in
                self?.play(prepared, generation: generation)
            }
        }
    }

    private func play(_ prepared: PreparedTrackerStream, generation: Int) {
        guard generation == renderGeneration, !isMuted else { return }
        guard let stream = prepared.stream else {
            send(.fail("Could not stream \(prepared.track.fileName): \(prepared.errorMessage ?? "Unknown error")"))
            return
        }
        install(stream, generation: generation)
        send(.trackReady(prepared.track, moduleTitle: prepared.moduleTitle, generation: generation))
        if !isPaused {
            guard ensureEngine() else { return }
            stream.play()
        }
    }

    private func ensureEngine() -> Bool {
        guard !isMuted, audioAvailable else { return false }
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            audioAvailable = false
            send(.fail(localizedErrorMessage(for: error)))
            return false
        }
    }

    private func install(_ stream: TrackerAudioStream, generation: Int) {
        let shouldResume = engine.isRunning && !isPaused
        if engine.isRunning {
            engine.pause()
        }
        detachActiveStream()
        activeStream = stream
        engine.attach(stream.playerNode)
        engine.connect(stream.playerNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        stream.startScheduling()
        startFinishPolling(generation: generation)
        if shouldResume {
            guard ensureEngine() else { return }
            stream.play()
        }
    }

    private func detachActiveStream() {
        stopFinishPolling()
        guard let activeStream else { return }
        activeStream.stop()
        engine.disconnectNodeOutput(activeStream.playerNode)
        engine.detach(activeStream.playerNode)
        self.activeStream = nil
    }

    private func startFinishPolling(generation: Int) {
        stopFinishPolling()
        finishPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else { return }
                guard self.activeStream?.isFinished == true else { continue }
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
        detachActiveStream()
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

private extension TrackerSoundtrackController {
    nonisolated static func prepareStream(
        for request: TrackerStreamRequest,
        effectsSettingsBox: SoundtrackEffectsSettingsBox
    ) -> PreparedTrackerStream {
        do {
            let stream = try TrackerAudioStream(
                request: request,
                effectsSettingsBox: effectsSettingsBox
            )
            return PreparedTrackerStream(
                track: request.track,
                stream: stream,
                moduleTitle: stream.moduleTitle,
                errorMessage: nil
            )
        } catch {
            return PreparedTrackerStream(
                track: request.track,
                stream: nil,
                moduleTitle: nil,
                errorMessage: error.localizedDescription
            )
        }
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
    case ready
    static var _blank: SoundtrackMachineState { .ready }
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

    var machine: some XStateMachine {
        XState(.ready) {
            XTransition(on: SoundtrackEvent.restore, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .restore(muted, volume, effects)? = args.event {
                    ctx.isMuted = muted
                    ctx.volume = min(1, max(0, volume))
                    ctx.effectsSettings = effects.normalized()
                    ctx.phase = muted ? .stopped : ctx.phase
                }
                return ctx
            }

            XTransition(on: SoundtrackEvent.setMuted, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .setMuted(muted)? = args.event {
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

            XTransition(on: SoundtrackEvent.setVolume, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .setVolume(volume)? = args.event {
                    ctx.volume = min(1, max(0, volume))
                }
                return ctx
            }

            XTransition(on: SoundtrackEvent.setEffects, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .setEffects(settings)? = args.event {
                    ctx.effectsSettings = settings.normalized()
                }
                return ctx
            }

            XTransition(on: SoundtrackEvent.setPurpose, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .setPurpose(purpose)? = args.event {
                    ctx.activePurpose = purpose
                }
                return ctx
            }

            XTransition(on: SoundtrackEvent.requestTrack, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .requestTrack(track, purpose, generation)? = args.event {
                    ctx.phase = .loading
                    ctx.currentTrack = track
                    ctx.nowPlaying = track.nowPlaying(moduleTitle: nil)
                    ctx.activePurpose = purpose
                    ctx.generation = generation
                    ctx.lastError = nil
                }
                return ctx
            }

            XTransition(on: SoundtrackEvent.trackReady, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .trackReady(track, moduleTitle, generation)? = args.event,
                   generation == ctx.generation {
                    ctx.currentTrack = track
                    ctx.nowPlaying = track.nowPlaying(moduleTitle: moduleTitle)
                    if ctx.phase != .paused {
                        ctx.phase = .playing
                    }
                    ctx.lastError = nil
                }
                return ctx
            }

            XTransition(on: SoundtrackEvent.pause, to: .ready).action { args, _ in
                var ctx = args.context
                guard !ctx.isMuted, ctx.currentTrack != nil else { return ctx }
                ctx.phase = .paused
                return ctx
            }

            XTransition(on: SoundtrackEvent.resume, to: .ready).action { args, _ in
                var ctx = args.context
                guard !ctx.isMuted else { return ctx }
                ctx.phase = ctx.currentTrack == nil ? .stopped : .playing
                return ctx
            }

            XTransition(on: SoundtrackEvent.stop, to: .ready).action { args, _ in
                var ctx = args.context
                ctx.phase = .stopped
                ctx.currentTrack = nil
                ctx.nowPlaying = .empty
                return ctx
            }

            XTransition(on: SoundtrackEvent.fail, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .fail(message)? = args.event {
                    ctx.phase = .failed
                    ctx.lastError = message
                }
                return ctx
            }

            XTransition(on: SoundtrackEvent.finish, to: .ready).action { args, _ in
                var ctx = args.context
                ctx.phase = .stopped
                return ctx
            }
        }
        .initial()
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

private nonisolated struct PreparedTrackerStream {
    let track: TrackerModuleTrack
    let stream: TrackerAudioStream?
    let moduleTitle: String?
    let errorMessage: String?
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

    func play() {
        guard !isFinished else { return }
        core.requestPlayback(on: playerNode)
    }

    func pause() {
        core.cancelPlaybackRequest()
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
    private let prerollFrameCount: Int
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
    private var playbackRequested = false
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
        prerollFrameCount = max(0, min(request.streamPrerollFrames, maxQueuedFrameCount))
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

    func stop() {
        condition.lock()
        stopRequested = true
        playbackRequested = false
        condition.broadcast()
        condition.unlock()
    }

    func requestPlayback(on playerNode: AVAudioPlayerNode) {
        let shouldPlay: Bool
        condition.lock()
        self.playerNode = playerNode
        if shouldStartPlaybackImmediatelyLocked {
            playbackRequested = false
            shouldPlay = true
        } else {
            playbackRequested = true
            shouldPlay = false
        }
        condition.unlock()

        if shouldPlay, !playerNode.isPlaying {
            playerNode.play()
        }
    }

    func cancelPlaybackRequest() {
        condition.lock()
        playbackRequested = false
        condition.broadcast()
        condition.unlock()
    }

    private func scheduleLoop() {
        while true {
            guard waitForSchedulingCapacity() else { return }
            guard let playerNode else { return }

            let remainingFrames = maxFrameCount - renderedFrameCount
            guard remainingFrames > 0 else {
                let shouldStartPlayback = markRenderComplete()
                if shouldStartPlayback, !playerNode.isPlaying {
                    playerNode.play()
                }
                return
            }

            let requestedFrames = min(renderChunkFrameCount, remainingFrames)
            let songFrames = renderer.renderSongFrames(frameCount: requestedFrames)
            guard songFrames.buffer.frameCount > 0 else {
                let shouldStartPlayback = markRenderComplete()
                if shouldStartPlayback, !playerNode.isPlaying {
                    playerNode.play()
                }
                return
            }

            renderedFrameCount += songFrames.buffer.frameCount
            let processed = effectsProcessor.process(songFrames.buffer, settings: effectsSettingsBox.get())
            guard let audioBuffer = makeAudioBuffer(from: processed) else {
                let shouldStartPlayback = markRenderComplete()
                if shouldStartPlayback, !playerNode.isPlaying {
                    playerNode.play()
                }
                return
            }

            let shouldStartPlayback = schedule(audioBuffer, on: playerNode)
            if shouldStartPlayback, !playerNode.isPlaying {
                playerNode.play()
            }

            if songFrames.isFinished || renderedFrameCount >= maxFrameCount {
                let shouldStartPlayback = markRenderComplete()
                if shouldStartPlayback, !playerNode.isPlaying {
                    playerNode.play()
                }
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

    private func schedule(_ buffer: AVAudioPCMBuffer, on playerNode: AVAudioPlayerNode) -> Bool {
        let frameCount = Int(buffer.frameLength)
        let shouldStartPlayback: Bool
        condition.lock()
        queuedFrameCount += frameCount
        shouldStartPlayback = shouldStartPlaybackLocked
        if shouldStartPlayback {
            playbackRequested = false
        }
        condition.broadcast()
        condition.unlock()

        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.bufferDidPlay(frameCount: frameCount)
        }
        return shouldStartPlayback
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

    private func markRenderComplete() -> Bool {
        let shouldStartPlayback: Bool
        let shouldFinish: Bool
        condition.lock()
        didRenderFinalBuffer = true
        shouldStartPlayback = shouldStartPlaybackLocked
        if shouldStartPlayback {
            playbackRequested = false
        }
        shouldFinish = !stopRequested && queuedFrameCount == 0
        condition.broadcast()
        condition.unlock()

        if shouldFinish {
            finishOnce()
        }
        return shouldStartPlayback
    }

    private var shouldStartPlaybackImmediatelyLocked: Bool {
        !stopRequested && !didFinish && (queuedFrameCount >= playbackStartFrameCount || didRenderFinalBuffer)
    }

    private var shouldStartPlaybackLocked: Bool {
        playbackRequested && shouldStartPlaybackImmediatelyLocked
    }

    private var playbackStartFrameCount: Int {
        min(max(1, prerollFrameCount), maxFrameCount)
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
