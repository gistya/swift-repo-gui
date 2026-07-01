import AVFoundation
import Combine
import Foundation

@MainActor
final class TrackerSoundtrackController: ObservableObject {
    private let soundStyle: SoundPalette
    private let sampleRate: Double
    private let format: AVAudioFormat
    private let engine = AVAudioEngine()
    private let loopPlayer = AVAudioPlayerNode()
    private let cuePlayer = AVAudioPlayerNode()
    private var currentStage: BuildStage = .off
    private var wasRunning = false
    private var audioAvailable = true

    init() {
        let style = SwiftBuilderStyle.current.sound
        soundStyle = style
        sampleRate = style.sampleRate
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.attach(loopPlayer)
        engine.attach(cuePlayer)
        engine.connect(loopPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(cuePlayer, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = style.masterVolume
        engine.prepare()
    }

    func update(for context: BuildOperationsContext) {
        let stage = BuildStage.stage(for: context)
        if context.isRunning, !wasRunning {
            playStartupCue()
        }
        if stage == .failed, currentStage != .failed {
            playFailureCue()
        } else if !context.isRunning, wasRunning, context.lastExitCode == 0 {
            playSuccessCue()
        }

        wasRunning = context.isRunning
        guard stage != currentStage else { return }
        currentStage = stage
        playLoop(for: stage)
    }

    private func playLoop(for stage: BuildStage) {
        loopPlayer.stop()
        guard stage != .off, stage != .failed, let buffer = makeLoopBuffer(for: stage) else { return }
        guard ensureEngine() else { return }
        loopPlayer.scheduleBuffer(buffer, at: nil, options: [.loops])
        loopPlayer.play()
    }

    private func playStartupCue() {
        playCue(makeStartupCue())
    }

    private func playFailureCue() {
        loopPlayer.stop()
        playCue(makeFailureCue())
    }

    private func playSuccessCue() {
        playCue(makeSuccessCue())
    }

    private func playCue(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer, ensureEngine() else { return }
        cuePlayer.stop()
        cuePlayer.scheduleBuffer(buffer)
        cuePlayer.play()
    }

    private func ensureEngine() -> Bool {
        guard audioAvailable else { return false }
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            audioAvailable = false
            return false
        }
    }

    private func makeLoopBuffer(for stage: BuildStage) -> AVAudioPCMBuffer? {
        let duration = soundStyle.loopDuration
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frameCount

        let pattern = pattern(for: stage)
        let bpm = bpm(for: stage)
        let secondsPerStep = 60.0 / bpm / 2.0
        let left = channels[0]
        let right = channels[1]

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let stepIndex = Int(t / secondsPerStep) % pattern.notes.count
            let stepStart = Double(Int(t / secondsPerStep)) * secondsPerStep
            let local = t - stepStart
            let envelope = envelope(at: local, length: secondsPerStep)
            let lead = pattern.notes[stepIndex]
            let bass = pattern.bass[(stepIndex / 2) % pattern.bass.count] / 2
            let hat = ((Int(t * pattern.hatRate) % 2) == 0 ? 1.0 : -1.0) * 0.025

            let leadWave = square(frequency: lead, time: t) * 0.10 * envelope
            let bassWave = saw(frequency: bass, time: t) * 0.055 * envelope
            let accent = stepIndex % pattern.accentEvery == 0 ? sin(2 * .pi * lead * 2 * t) * 0.05 * envelope : 0
            let sample = softClip(leadWave + bassWave + accent + hat)
            left[frame] = Float(sample * pattern.leftBias)
            right[frame] = Float(sample * pattern.rightBias)
        }

        return buffer
    }

    private func makeStartupCue() -> AVAudioPCMBuffer? {
        let duration = soundStyle.startupCueDuration
        return makeCue(duration: duration) { t in
            let fade = min(1, t / 0.28) * max(0, min(1, (duration - t) / 0.55))
            let glide = 1 + 0.015 * sin(2 * .pi * t)
            let chord = sine(261.63 * glide, t) + sine(329.63 * glide, t) + sine(392.0 * glide, t) + sine(523.25 * glide, t)
            return softClip(chord * 0.095 * fade)
        }
    }

    private func makeFailureCue() -> AVAudioPCMBuffer? {
        let duration = soundStyle.failureCueDuration
        return makeCue(duration: duration) { t in
            let fade = max(0, min(1, (duration - t) / 1.2))
            let wobble = 1 + 0.035 * sin(2 * .pi * 5.5 * t)
            let down = max(80, 185 - 52 * t)
            let chord = square(frequency: down * wobble, time: t) +
                square(frequency: down * 0.75 * wobble, time: t) +
                sine(down * 1.5 * wobble, t)
            return softClip(chord * 0.10 * fade)
        }
    }

    private func makeSuccessCue() -> AVAudioPCMBuffer? {
        let duration = soundStyle.successCueDuration
        return makeCue(duration: duration) { t in
            let fade = min(1, t / 0.04) * max(0, min(1, (duration - t) / 0.35))
            let note = t < 0.28 ? 523.25 : (t < 0.56 ? 659.25 : 783.99)
            return softClip((sine(note, t) + sine(note * 2, t) * 0.4) * 0.11 * fade)
        }
    }

    private func makeCue(duration: Double, sample: (Double) -> Double) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let value = sample(t)
            channels[0][frame] = Float(value)
            channels[1][frame] = Float(value)
        }
        return buffer
    }

    private func pattern(for stage: BuildStage) -> TrackerPattern {
        switch stage {
        case .building:
            TrackerPattern(
                notes: [392, 493.88, 587.33, 493.88, 659.25, 587.33, 493.88, 392],
                bass: [98, 123.47, 146.83, 123.47],
                hatRate: 18,
                accentEvery: 4,
                leftBias: 0.94,
                rightBias: 1.06
            )
        case .testing:
            TrackerPattern(
                notes: [440, 440, 523.25, 392, 493.88, 349.23, 523.25, 659.25],
                bass: [110, 110, 130.81, 98],
                hatRate: 24,
                accentEvery: 3,
                leftBias: 1.05,
                rightBias: 0.95
            )
        case .measuring:
            TrackerPattern(
                notes: [329.63, 392, 493.88, 587.33, 493.88, 392, 329.63, 293.66],
                bass: [82.41, 98, 123.47, 98],
                hatRate: 12,
                accentEvery: 8,
                leftBias: 0.98,
                rightBias: 1.02
            )
        case .deploying:
            TrackerPattern(
                notes: [523.25, 587.33, 659.25, 783.99, 880, 783.99, 659.25, 587.33],
                bass: [130.81, 146.83, 164.81, 196],
                hatRate: 20,
                accentEvery: 4,
                leftBias: 1.04,
                rightBias: 0.96
            )
        case .off, .failed:
            TrackerPattern(
                notes: [440],
                bass: [110],
                hatRate: 1,
                accentEvery: 1,
                leftBias: 1,
                rightBias: 1
            )
        }
    }

    private func bpm(for stage: BuildStage) -> Double {
        switch stage {
        case .building: soundStyle.buildingBPM
        case .testing: soundStyle.testingBPM
        case .measuring: soundStyle.measuringBPM
        case .deploying: soundStyle.deployingBPM
        case .off, .failed: 120
        }
    }
}

private struct TrackerPattern {
    let notes: [Double]
    let bass: [Double]
    let hatRate: Double
    let accentEvery: Int
    let leftBias: Double
    let rightBias: Double
}

private func envelope(at time: Double, length: Double) -> Double {
    let attack = min(1, time / 0.018)
    let release = max(0, min(1, (length - time) / 0.12))
    return attack * release
}

private func sine(_ frequency: Double, _ time: Double) -> Double {
    sin(2 * .pi * frequency * time)
}

private func square(frequency: Double, time: Double) -> Double {
    sine(frequency, time) >= 0 ? 1 : -1
}

private func saw(frequency: Double, time: Double) -> Double {
    let phase = (frequency * time).truncatingRemainder(dividingBy: 1)
    return 2 * phase - 1
}

private func softClip(_ value: Double) -> Double {
    tanh(value * 1.35)
}
