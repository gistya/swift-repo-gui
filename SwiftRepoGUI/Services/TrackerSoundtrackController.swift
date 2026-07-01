import AVFoundation
import Combine
import Foundation

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
        guard !startupPlayed else { return }
        startupPlayed = true
        guard !isMuted else { return }
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
            if startupPlayed {
                currentStage = .off
                update(for: lastContext, forceStageRefresh: true)
            } else {
                start()
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
            lastError = "Could not render \(rendered.track.fileName)."
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
        return RenderedTrackerBuffer(track: request.track, buffer: renderer.render())
    }
}

nonisolated struct TrackerModuleTrack: Hashable, Sendable {
    let url: URL
    let fileName: String
    let title: String
    let format: String
}

nonisolated enum TrackerModuleLibrary {
    static let supportedExtensions = ["mod", "xm", "it", "s3m", "mptm"]

    static func discover(in bundle: Bundle = .main) -> [TrackerModuleTrack] {
        var urls = Set<URL>()
        let subdirectories: [String?] = [
            "TrackerModules",
            "Resources/TrackerModules",
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

private struct TrackerRenderRequest: Sendable {
    let track: TrackerModuleTrack
    let purpose: SoundtrackPurpose
    let sampleRate: Double
    let duration: Double
    let soundStyle: SoundPalette
}

private struct RenderedTrackerBuffer {
    let track: TrackerModuleTrack
    let buffer: AVAudioPCMBuffer?
}

private enum SoundtrackPurpose: Sendable, Equatable {
    case startup
    case stage(BuildStage)
    case success
    case failure
    case test
}

private struct TrackerRenderer {
    let request: TrackerRenderRequest

    private var format: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: request.sampleRate, channels: 2)!
    }

    func render() -> AVAudioPCMBuffer? {
        let seed = Self.seed(for: request.track.url)
        let pattern = pattern(seed: seed)
        let frameCount = AVAudioFrameCount(request.duration * request.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frameCount

        let secondsPerStep = 60.0 / pattern.bpm / 4.0
        let left = channels[0]
        let right = channels[1]

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / request.sampleRate
            let position = t / secondsPerStep
            let step = Int(position) % pattern.stepCount
            let local = t - Double(Int(position)) * secondsPerStep
            let stepProgress = local / secondsPerStep
            let barProgress = (t.truncatingRemainder(dividingBy: secondsPerStep * Double(pattern.stepCount))) /
                (secondsPerStep * Double(pattern.stepCount))

            let lead = leadSample(pattern: pattern, step: step, local: local, stepProgress: stepProgress, time: t)
            let bass = bassSample(pattern: pattern, step: step, local: local, time: t)
            let pad = padSample(pattern: pattern, barProgress: barProgress, time: t)
            let drums = drumSample(pattern: pattern, step: step, local: local, time: t, frame: frame)
            let shimmer = shimmerSample(pattern: pattern, step: step, local: local, time: t, frame: frame)

            let pan = pattern.panForStep[step % pattern.panForStep.count]
            let mixed = softClip((lead + bass + pad + drums + shimmer) * pattern.outputGain)
            left[frame] = Float(mixed * (1 - max(0, pan) * 0.22))
            right[frame] = Float(mixed * (1 + min(0, pan) * 0.22))
        }

        return buffer
    }

    private func pattern(seed: UInt64) -> TrackerPattern {
        let base = basePattern(for: request.purpose)
        let transposeChoices = [-5, -2, 0, 2, 5, 7]
        let rotate = Int(seed % UInt64(max(1, base.melody.count)))
        let transpose = transposeChoices[Int((seed >> 8) % UInt64(transposeChoices.count))]
        let bpmDrift = Double(Int((seed >> 16) % 13) - 6)
        let gain = 0.88 + Double((seed >> 24) % 9) / 100

        return TrackerPattern(
            bpm: max(88, base.bpm + bpmDrift),
            melody: rotateNotes(base.melody, by: rotate, transpose: transpose),
            bass: rotateNotes(base.bass, by: rotate / 2, transpose: transpose),
            padChord: base.padChord.map { max(24, $0 + transpose) },
            arp: rotateInts(base.arp, by: Int((seed >> 32) % UInt64(max(1, base.arp.count)))),
            kickSteps: base.kickSteps,
            snareSteps: base.snareSteps,
            hatSteps: base.hatSteps,
            panForStep: base.panForStep.map { (seed & 1) == 0 ? $0 : -$0 },
            leadLevel: base.leadLevel,
            bassLevel: base.bassLevel,
            padLevel: base.padLevel,
            kickLevel: base.kickLevel,
            snareLevel: base.snareLevel,
            hatLevel: base.hatLevel,
            outputGain: base.outputGain * gain,
            leadDecay: base.leadDecay
        )
    }

    private func basePattern(for purpose: SoundtrackPurpose) -> TrackerPattern {
        switch purpose {
        case .startup:
            return basePattern(for: .stage(.building)).withBPM(118).withPadLevel(0.72)
        case .success, .test:
            return basePattern(for: .stage(.deploying)).withBPM(132).withPadLevel(0.58)
        case .failure:
            return TrackerPattern(
                bpm: 96,
                melody: [48, nil, 43, nil, 41, nil, 36, nil, 43, nil, 41, nil, 36, nil, nil, nil],
                bass: [24, nil, nil, 31, nil, nil, 29, nil, 24, nil, 31, nil, 29, nil, nil, nil],
                padChord: [36, 43, 48],
                arp: [0, 3, 7, 10],
                kickSteps: [0, 8],
                snareSteps: [12],
                hatSteps: [6, 14],
                panForStep: [-0.08, 0.08, -0.12, 0.12],
                leadLevel: 0.14,
                bassLevel: 0.18,
                padLevel: 0.78,
                kickLevel: 0.18,
                snareLevel: 0.07,
                hatLevel: 0.018,
                outputGain: 0.64,
                leadDecay: 0.68
            )
        case let .stage(stage):
            switch stage {
            case .testing:
                return TrackerPattern(
                    bpm: request.soundStyle.testingBPM,
                    melody: [64, 67, 71, nil, 76, 74, 71, 67, 66, 69, 73, nil, 78, 76, 73, 69],
                    bass: [40, nil, 47, nil, 40, 47, nil, 52, 42, nil, 49, nil, 42, 49, nil, 54],
                    padChord: [52, 59, 64],
                    arp: [0, 4, 7, 12],
                    kickSteps: [0, 6, 10],
                    snareSteps: [4, 12],
                    hatSteps: [0, 2, 4, 6, 8, 10, 12, 14],
                    panForStep: [0.28, -0.18, 0.12, -0.26],
                    leadLevel: 0.18,
                    bassLevel: 0.15,
                    padLevel: 0.42,
                    kickLevel: 0.20,
                    snareLevel: 0.10,
                    hatLevel: 0.040,
                    outputGain: 0.68,
                    leadDecay: 0.20
                )
            case .measuring:
                return TrackerPattern(
                    bpm: request.soundStyle.measuringBPM,
                    melody: [55, nil, 62, nil, 67, nil, 62, nil, 57, nil, 64, nil, 69, nil, 64, nil],
                    bass: [31, nil, nil, 38, nil, nil, 43, nil, 33, nil, nil, 40, nil, nil, 45, nil],
                    padChord: [43, 50, 55, 62],
                    arp: [0, 7, 12, 7],
                    kickSteps: [0],
                    snareSteps: [12],
                    hatSteps: [6, 14],
                    panForStep: [-0.12, 0.12, -0.08, 0.08],
                    leadLevel: 0.15,
                    bassLevel: 0.13,
                    padLevel: 0.82,
                    kickLevel: 0.14,
                    snareLevel: 0.07,
                    hatLevel: 0.025,
                    outputGain: 0.66,
                    leadDecay: 0.58
                )
            case .deploying:
                return TrackerPattern(
                    bpm: request.soundStyle.deployingBPM,
                    melody: [67, 71, 74, 79, 76, 74, 71, 67, 69, 72, 76, 81, 79, 76, 72, 69],
                    bass: [43, nil, 50, nil, 43, nil, 50, 55, 45, nil, 52, nil, 45, nil, 52, 57],
                    padChord: [55, 62, 67],
                    arp: [0, 4, 7, 12],
                    kickSteps: [0, 8, 11],
                    snareSteps: [4, 12],
                    hatSteps: [2, 4, 6, 10, 12, 14],
                    panForStep: [-0.30, -0.10, 0.12, 0.30],
                    leadLevel: 0.19,
                    bassLevel: 0.17,
                    padLevel: 0.50,
                    kickLevel: 0.22,
                    snareLevel: 0.10,
                    hatLevel: 0.040,
                    outputGain: 0.70,
                    leadDecay: 0.26
                )
            case .building, .off, .failed:
                return TrackerPattern(
                    bpm: request.soundStyle.buildingBPM,
                    melody: [60, nil, 67, 72, 64, nil, 67, 76, 62, nil, 69, 74, 64, 67, nil, 71],
                    bass: [36, nil, 36, 43, 36, nil, 43, nil, 38, nil, 38, 45, 40, nil, 40, 47],
                    padChord: [48, 55, 60],
                    arp: [0, 7, 12, 7],
                    kickSteps: [0, 8],
                    snareSteps: [4, 12],
                    hatSteps: [2, 6, 10, 14],
                    panForStep: [-0.25, 0.05, 0.22, -0.08],
                    leadLevel: 0.20,
                    bassLevel: 0.18,
                    padLevel: 0.55,
                    kickLevel: 0.24,
                    snareLevel: 0.11,
                    hatLevel: 0.045,
                    outputGain: 0.72,
                    leadDecay: 0.32
                )
            }
        }
    }

    private func leadSample(
        pattern: TrackerPattern,
        step: Int,
        local: Double,
        stepProgress: Double,
        time: Double
    ) -> Double {
        guard let note = pattern.melody[step % pattern.melody.count] else { return 0 }
        let arpOffset = pattern.arp[Int(stepProgress * Double(pattern.arp.count)) % pattern.arp.count]
        let frequency = midiFrequency(Double(note + arpOffset))
        let vibrato = 1 + 0.0025 * sine(5.2, time)
        let env = pluckEnvelope(at: local, attack: 0.012, decay: pattern.leadDecay)
        let voice = triangle(frequency: frequency * vibrato, time: time) * 0.55 +
            sine(frequency * 2.0, time) * 0.12
        return voice * env * pattern.leadLevel
    }

    private func bassSample(pattern: TrackerPattern, step: Int, local: Double, time: Double) -> Double {
        guard let note = pattern.bass[step % pattern.bass.count] else { return 0 }
        let frequency = midiFrequency(Double(note))
        let env = pluckEnvelope(at: local, attack: 0.008, decay: 0.42)
        let voice = roundedPulse(frequency: frequency, time: time) * 0.62 +
            sine(frequency * 0.5, time) * 0.25
        return voice * env * pattern.bassLevel
    }

    private func padSample(pattern: TrackerPattern, barProgress: Double, time: Double) -> Double {
        let swell = 0.5 - 0.5 * cos(2 * .pi * barProgress)
        let chord = pattern.padChord.reduce(0.0) { partial, note in
            partial + sine(midiFrequency(Double(note)), time)
        } / Double(max(1, pattern.padChord.count))
        return chord * (0.08 + swell * 0.04) * pattern.padLevel
    }

    private func drumSample(
        pattern: TrackerPattern,
        step: Int,
        local: Double,
        time: Double,
        frame: Int
    ) -> Double {
        var sample = 0.0
        if pattern.kickSteps.contains(step) {
            let env = exp(-local * 18)
            let pitch = 52 + 48 * exp(-local * 24)
            sample += sine(pitch, time) * env * pattern.kickLevel
        }
        if pattern.snareSteps.contains(step) {
            let env = exp(-local * 24)
            sample += whiteNoise(frame) * env * pattern.snareLevel
            sample += triangle(frequency: 176, time: time) * env * pattern.snareLevel * 0.25
        }
        return sample
    }

    private func shimmerSample(
        pattern: TrackerPattern,
        step: Int,
        local: Double,
        time: Double,
        frame: Int
    ) -> Double {
        guard pattern.hatSteps.contains(step) else { return 0 }
        let env = exp(-local * 72)
        let metallic = triangle(frequency: 7_040, time: time) * 0.18 + whiteNoise(frame) * 0.82
        return metallic * env * pattern.hatLevel
    }

    private static func seed(for url: URL) -> UInt64 {
        let data = (try? Data(contentsOf: url, options: [.mappedIfSafe])) ?? Data(url.lastPathComponent.utf8)
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data.prefix(256 * 1024) {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        hash ^= UInt64(data.count)
        return hash
    }

    private func rotateNotes(_ notes: [Int?], by offset: Int, transpose: Int) -> [Int?] {
        guard !notes.isEmpty else { return notes }
        return notes.indices.map { index in
            let note = notes[(index + offset) % notes.count]
            return note.map { max(12, $0 + transpose) }
        }
    }

    private func rotateInts(_ values: [Int], by offset: Int) -> [Int] {
        guard !values.isEmpty else { return values }
        return values.indices.map { values[($0 + offset) % values.count] }
    }
}

private struct TrackerPattern {
    let bpm: Double
    let melody: [Int?]
    let bass: [Int?]
    let padChord: [Int]
    let arp: [Int]
    let kickSteps: Set<Int>
    let snareSteps: Set<Int>
    let hatSteps: Set<Int>
    let panForStep: [Double]
    let leadLevel: Double
    let bassLevel: Double
    let padLevel: Double
    let kickLevel: Double
    let snareLevel: Double
    let hatLevel: Double
    let outputGain: Double
    let leadDecay: Double

    var stepCount: Int {
        max(melody.count, bass.count, 16)
    }

    func withBPM(_ bpm: Double) -> TrackerPattern {
        TrackerPattern(
            bpm: bpm,
            melody: melody,
            bass: bass,
            padChord: padChord,
            arp: arp,
            kickSteps: kickSteps,
            snareSteps: snareSteps,
            hatSteps: hatSteps,
            panForStep: panForStep,
            leadLevel: leadLevel,
            bassLevel: bassLevel,
            padLevel: padLevel,
            kickLevel: kickLevel,
            snareLevel: snareLevel,
            hatLevel: hatLevel,
            outputGain: outputGain,
            leadDecay: leadDecay
        )
    }

    func withPadLevel(_ padLevel: Double) -> TrackerPattern {
        TrackerPattern(
            bpm: bpm,
            melody: melody,
            bass: bass,
            padChord: padChord,
            arp: arp,
            kickSteps: kickSteps,
            snareSteps: snareSteps,
            hatSteps: hatSteps,
            panForStep: panForStep,
            leadLevel: leadLevel,
            bassLevel: bassLevel,
            padLevel: padLevel,
            kickLevel: kickLevel,
            snareLevel: snareLevel,
            hatLevel: hatLevel,
            outputGain: outputGain,
            leadDecay: leadDecay
        )
    }
}

private func pluckEnvelope(at time: Double, attack: Double, decay: Double) -> Double {
    min(1, time / attack) * exp(-time / decay)
}

private func midiFrequency(_ note: Double) -> Double {
    440 * pow(2, (note - 69) / 12)
}

private func sine(_ frequency: Double, _ time: Double) -> Double {
    sin(2 * .pi * frequency * time)
}

private func triangle(frequency: Double, time: Double) -> Double {
    let phase = (frequency * time).truncatingRemainder(dividingBy: 1)
    return 4 * abs(phase - 0.5) - 1
}

private func roundedPulse(frequency: Double, time: Double) -> Double {
    tanh(sine(frequency, time) * 2.4) / tanh(2.4)
}

private func whiteNoise(_ frame: Int) -> Double {
    var value = UInt64(truncatingIfNeeded: frame) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    value ^= value >> 33
    value &*= 0xff51afd7ed558ccd
    value ^= value >> 33
    return (Double(value & 0xffff) / 32_768) - 1
}

private func softClip(_ value: Double) -> Double {
    tanh(value * 1.18)
}
