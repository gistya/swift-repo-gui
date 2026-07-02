import AVFoundation
import Combine
import Foundation
import Ox0badf00d

@MainActor
final class TrackerSoundtrackController: ObservableObject {
    @Published private(set) var isMuted = false
    @Published private(set) var lastError: String?

    private let soundStyle: SoundPalette
    private let sampleRate: Double
    private let format: AVAudioFormat
    private let engine = AVAudioEngine()
    private let loopPlayer = AVAudioPlayerNode()
    private let renderQueue = DispatchQueue(label: "SwiftBuilder.Soundtrack.Render", qos: .userInitiated)
    private var renderGeneration = 0
    private var currentStage: BuildStage = .off
    private var currentTrack: TrackerModuleTrack?
    private var wasRunning = false
    private var audioAvailable = true
    private var startupPlayed = false
    private var lastContext = BuildOperationsContext()
    private let tracks: [TrackerModuleTrack]

    init() {
        let style = SwiftBuilderStyle.current.sound
        soundStyle = style
        sampleRate = style.sampleRate
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        tracks = TrackerModuleLibrary.discover()

        engine.attach(loopPlayer)
        engine.connect(loopPlayer, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = style.masterVolume
        engine.prepare()
    }

    func start() {
        guard !startupPlayed, !isMuted else { return }
        startupPlayed = true
        playRandomTrack(for: .startup)
    }

    func setMuted(_ muted: Bool) {
        guard isMuted != muted else { return }
        isMuted = muted
        if muted {
            stopAll()
        } else {
            audioAvailable = true
            lastError = nil
            if lastContext.isRunning {
                currentStage = .off
                update(for: lastContext, forceStageRefresh: true)
            } else {
                startupPlayed = true
                playRandomTrack(for: .startup)
            }
        }
    }

    func update(for context: BuildOperationsContext) {
        update(for: context, forceStageRefresh: false)
    }

    func playTestCue() {
        guard !isMuted else { return }
        playRandomTrack(for: .test)
    }

    private func update(for context: BuildOperationsContext, forceStageRefresh: Bool) {
        lastContext = context
        let stage = BuildStage.stage(for: context)

        if isMuted {
            wasRunning = context.isRunning
            currentStage = stage
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

    private func stopAll() {
        renderGeneration += 1
        loopPlayer.stop()
        if engine.isRunning {
            engine.pause()
        }
    }

    private func playRandomTrack(for purpose: SoundtrackPurpose) {
        guard let track = randomTrack() else {
            lastError = "No tracker modules were found in the app bundle."
            return
        }

        renderGeneration += 1
        let generation = renderGeneration
        let request = TrackerRenderRequest(
            track: track,
            purpose: purpose,
            sampleRate: sampleRate,
            duration: duration(for: purpose),
            soundStyle: soundStyle
        )

        renderQueue.async { [weak self] in
            let rendered = Self.renderBuffer(for: request)
            DispatchQueue.main.async { [weak self] in
                self?.play(rendered, generation: generation)
            }
        }
    }

    private func play(_ rendered: RenderedTrackerBuffer, generation: Int) {
        guard generation == renderGeneration, !isMuted else { return }
        guard let buffer = rendered.buffer else {
            if let errorMessage = rendered.errorMessage {
                lastError = "Could not render \(rendered.track.fileName): \(errorMessage)"
            } else {
                lastError = "Could not render \(rendered.track.fileName)."
            }
            return
        }
        guard ensureEngine() else { return }

        currentTrack = rendered.track
        lastError = nil
        loopPlayer.stop()
        loopPlayer.scheduleBuffer(buffer, at: nil, options: [.loops])
        loopPlayer.play()
    }

    private func ensureEngine() -> Bool {
        guard !isMuted, audioAvailable else { return false }
        if engine.isRunning { return true }
        do {
            try engine.start()
            lastError = nil
            return true
        } catch {
            audioAvailable = false
            lastError = localizedErrorMessage(for: error)
            return false
        }
    }

    private func randomTrack() -> TrackerModuleTrack? {
        guard !tracks.isEmpty else { return nil }
        let candidates = tracks.count > 1 ? tracks.filter { $0 != currentTrack } : tracks
        return candidates.randomElement() ?? tracks.randomElement()
    }

    private func duration(for purpose: SoundtrackPurpose) -> Double {
        switch purpose {
        case .startup:
            max(10, soundStyle.loopDuration)
        case .success:
            max(6, soundStyle.successCueDuration * 4)
        case .failure:
            max(6, soundStyle.failureCueDuration * 4)
        case .test:
            max(4, soundStyle.successCueDuration * 4)
        case .stage:
            soundStyle.loopDuration
        }
    }
}

private extension TrackerSoundtrackController {
    nonisolated static func renderBuffer(for request: TrackerRenderRequest) -> RenderedTrackerBuffer {
        let renderer = TrackerRenderer(request: request)
        do {
            return RenderedTrackerBuffer(
                track: request.track,
                buffer: try renderer.render(),
                errorMessage: nil
            )
        } catch {
            return RenderedTrackerBuffer(
                track: request.track,
                buffer: nil,
                errorMessage: error.localizedDescription
            )
        }
    }
}

nonisolated struct TrackerModuleTrack: Hashable, Sendable {
    let url: URL
    let fileName: String
    let title: String
    let format: String
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

private nonisolated struct TrackerRenderRequest: Sendable {
    let track: TrackerModuleTrack
    let purpose: SoundtrackPurpose
    let sampleRate: Double
    let duration: Double
    let soundStyle: SoundPalette
}

private nonisolated struct RenderedTrackerBuffer {
    let track: TrackerModuleTrack
    let buffer: AVAudioPCMBuffer?
    let errorMessage: String?
}

private nonisolated enum SoundtrackPurpose: Sendable, Equatable {
    case startup
    case stage(BuildStage)
    case success
    case failure
    case test
}

private nonisolated struct TrackerRenderer {
    let request: TrackerRenderRequest

    private var format: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: request.sampleRate, channels: 2)!
    }

    func render() throws -> AVAudioPCMBuffer? {
        let module = try ModuleLoader.load(url: request.track.url)
        let pcm = ModuleRenderer(
            module: module,
            sampleRate: Int(request.sampleRate.rounded()),
            options: RenderOptions(
                spatialization: .psychoacoustic3D(.spacious),
                gain: gain(for: request.purpose)
            )
        ).render(seconds: request.duration)

        return makeAudioBuffer(from: pcm)
    }

    private func makeAudioBuffer(from pcm: PCMBuffer) -> AVAudioPCMBuffer? {
        guard pcm.channelCount == 2 else { return nil }
        let frameCount = AVAudioFrameCount(pcm.frameCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else { return nil }

        buffer.frameLength = frameCount
        let left = channels[0]
        let right = channels[1]
        for frame in 0..<pcm.frameCount {
            let sourceIndex = frame * pcm.channelCount
            left[frame] = pcm.interleavedSamples[sourceIndex]
            right[frame] = pcm.interleavedSamples[sourceIndex + 1]
        }
        return buffer
    }

    private func gain(for purpose: SoundtrackPurpose) -> Double {
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
