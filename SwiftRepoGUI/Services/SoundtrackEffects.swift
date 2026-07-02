import Foundation
import Ox0badf00d

nonisolated struct SoundtrackEffectsSettings: Codable, Equatable, Hashable, Sendable {
    var isEnabled: Bool
    var drive: Double
    var lowGainDB: Double
    var midGainDB: Double
    var highGainDB: Double
    var compression: Double
    var limiterCeilingDB: Double
    var outputGainDB: Double

    static let `default` = SoundtrackEffectsSettings(
        isEnabled: true,
        drive: 0.22,
        lowGainDB: 1.5,
        midGainDB: -0.5,
        highGainDB: 1.8,
        compression: 0.32,
        limiterCeilingDB: -1.2,
        outputGainDB: 0
    )

    func normalized() -> SoundtrackEffectsSettings {
        SoundtrackEffectsSettings(
            isEnabled: isEnabled,
            drive: Self.clamp(drive, 0...1),
            lowGainDB: Self.clamp(lowGainDB, -12...12),
            midGainDB: Self.clamp(midGainDB, -12...12),
            highGainDB: Self.clamp(highGainDB, -12...12),
            compression: Self.clamp(compression, 0...1),
            limiterCeilingDB: Self.clamp(limiterCeilingDB, -18...0),
            outputGainDB: Self.clamp(outputGainDB, -12...12)
        )
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }
}

nonisolated enum SoundtrackEffectsSettingsStore {
    static let defaultsKey = "SwiftBuilder.soundtrackEffects"

    static func load(from defaults: UserDefaults = .standard) -> SoundtrackEffectsSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(SoundtrackEffectsSettings.self, from: data) else {
            return .default
        }
        return decoded.normalized()
    }

    static func save(_ settings: SoundtrackEffectsSettings, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings.normalized()) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

nonisolated final class SoundtrackEffectsProcessor: @unchecked Sendable {
    private let sampleRate: Double
    private var leftLowShelf: Biquad
    private var rightLowShelf: Biquad
    private var leftMidPeak: Biquad
    private var rightMidPeak: Biquad
    private var leftHighShelf: Biquad
    private var rightHighShelf: Biquad
    private var currentSettings = SoundtrackEffectsSettings.default.normalized()
    private var compressorEnvelope = 0.0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        let settings = SoundtrackEffectsSettings.default.normalized()
        leftLowShelf = .lowShelf(sampleRate: sampleRate, frequency: 180, gainDB: settings.lowGainDB)
        rightLowShelf = leftLowShelf
        leftMidPeak = .peaking(sampleRate: sampleRate, frequency: 1_100, q: 0.85, gainDB: settings.midGainDB)
        rightMidPeak = leftMidPeak
        leftHighShelf = .highShelf(sampleRate: sampleRate, frequency: 5_800, gainDB: settings.highGainDB)
        rightHighShelf = leftHighShelf
        currentSettings = settings
    }

    func process(_ buffer: PCMBuffer, settings rawSettings: SoundtrackEffectsSettings) -> PCMBuffer {
        let settings = rawSettings.normalized()
        guard settings.isEnabled, buffer.channelCount == 2 else { return buffer }
        updateFiltersIfNeeded(settings)

        var output = buffer.interleavedSamples
        let attackCoefficient = exp(-1 / (0.012 * sampleRate))
        let releaseCoefficient = exp(-1 / (0.160 * sampleRate))
        let thresholdDB = -8 - settings.compression * 22
        let ratio = 1 + settings.compression * 7
        let makeupDB = settings.compression * 4
        let ceiling = dbToLinear(settings.limiterCeilingDB)
        let outputGain = dbToLinear(settings.outputGainDB)
        let driveGain = dbToLinear(settings.drive * 18)
        let driveShape = 1 + settings.drive * 5
        let wet = 0.28 + settings.drive * 0.72

        for frame in 0..<buffer.frameCount {
            let index = frame * 2
            var left = Double(output[index])
            var right = Double(output[index + 1])

            left = leftHighShelf.process(leftMidPeak.process(leftLowShelf.process(left)))
            right = rightHighShelf.process(rightMidPeak.process(rightLowShelf.process(right)))

            left = tube(left, driveGain: driveGain, driveShape: driveShape, wet: wet)
            right = tube(right, driveGain: driveGain, driveShape: driveShape, wet: wet)

            let level = max(abs(left), abs(right), 0.000_001)
            let coefficient = level > compressorEnvelope ? attackCoefficient : releaseCoefficient
            compressorEnvelope = coefficient * compressorEnvelope + (1 - coefficient) * level
            let envelopeDB = linearToDB(max(compressorEnvelope, 0.000_001))

            var gainDB = makeupDB
            if envelopeDB > thresholdDB {
                let compressedDB = thresholdDB + (envelopeDB - thresholdDB) / ratio
                gainDB += compressedDB - envelopeDB
            }

            let dynamicsGain = dbToLinear(gainDB) * outputGain
            left *= dynamicsGain
            right *= dynamicsGain

            let peak = max(abs(left), abs(right))
            if peak > ceiling, peak > 0 {
                let scale = ceiling / peak
                left = softLimit(left * scale, ceiling: ceiling)
                right = softLimit(right * scale, ceiling: ceiling)
            }

            output[index] = Float(left)
            output[index + 1] = Float(right)
        }

        return PCMBuffer(sampleRate: buffer.sampleRate, channelCount: buffer.channelCount, interleavedSamples: output)
    }

    private func updateFiltersIfNeeded(_ settings: SoundtrackEffectsSettings) {
        guard settings.lowGainDB != currentSettings.lowGainDB ||
            settings.midGainDB != currentSettings.midGainDB ||
            settings.highGainDB != currentSettings.highGainDB else {
            currentSettings = settings
            return
        }

        leftLowShelf.updateCoefficients(.lowShelf(sampleRate: sampleRate, frequency: 180, gainDB: settings.lowGainDB))
        rightLowShelf.updateCoefficients(.lowShelf(sampleRate: sampleRate, frequency: 180, gainDB: settings.lowGainDB))
        leftMidPeak.updateCoefficients(.peaking(sampleRate: sampleRate, frequency: 1_100, q: 0.85, gainDB: settings.midGainDB))
        rightMidPeak.updateCoefficients(.peaking(sampleRate: sampleRate, frequency: 1_100, q: 0.85, gainDB: settings.midGainDB))
        leftHighShelf.updateCoefficients(.highShelf(sampleRate: sampleRate, frequency: 5_800, gainDB: settings.highGainDB))
        rightHighShelf.updateCoefficients(.highShelf(sampleRate: sampleRate, frequency: 5_800, gainDB: settings.highGainDB))
        currentSettings = settings
    }

    private func tube(_ sample: Double, driveGain: Double, driveShape: Double, wet: Double) -> Double {
        let driven = sample * driveGain
        let shaped = tanh(driven * driveShape) / tanh(driveShape)
        return sample * (1 - wet) + shaped * wet
    }

    private func softLimit(_ sample: Double, ceiling: Double) -> Double {
        ceiling * tanh(sample / max(0.000_001, ceiling))
    }
}

private nonisolated struct Biquad {
    private var b0: Double
    private var b1: Double
    private var b2: Double
    private var a1: Double
    private var a2: Double
    private var z1 = 0.0
    private var z2 = 0.0

    private init(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) {
        self.b0 = b0 / a0
        self.b1 = b1 / a0
        self.b2 = b2 / a0
        self.a1 = a1 / a0
        self.a2 = a2 / a0
    }

    mutating func process(_ input: Double) -> Double {
        let output = b0 * input + z1
        z1 = b1 * input - a1 * output + z2
        z2 = b2 * input - a2 * output
        return output
    }

    mutating func updateCoefficients(_ coefficients: Biquad) {
        b0 = coefficients.b0
        b1 = coefficients.b1
        b2 = coefficients.b2
        a1 = coefficients.a1
        a2 = coefficients.a2
    }

    static func peaking(sampleRate: Double, frequency: Double, q: Double, gainDB: Double) -> Biquad {
        let omega = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(omega) / (2 * q)
        let cosine = cos(omega)
        let amplitude = pow(10, gainDB / 40)

        return Biquad(
            b0: 1 + alpha * amplitude,
            b1: -2 * cosine,
            b2: 1 - alpha * amplitude,
            a0: 1 + alpha / amplitude,
            a1: -2 * cosine,
            a2: 1 - alpha / amplitude
        )
    }

    static func lowShelf(sampleRate: Double, frequency: Double, gainDB: Double) -> Biquad {
        shelf(sampleRate: sampleRate, frequency: frequency, gainDB: gainDB, isHighShelf: false)
    }

    static func highShelf(sampleRate: Double, frequency: Double, gainDB: Double) -> Biquad {
        shelf(sampleRate: sampleRate, frequency: frequency, gainDB: gainDB, isHighShelf: true)
    }

    private static func shelf(
        sampleRate: Double,
        frequency: Double,
        gainDB: Double,
        isHighShelf: Bool
    ) -> Biquad {
        let amplitude = pow(10, gainDB / 40)
        let omega = 2 * Double.pi * frequency / sampleRate
        let sine = sin(omega)
        let cosine = cos(omega)
        let alpha = sine / 2 * sqrt(2)
        let beta = 2 * sqrt(amplitude) * alpha

        if isHighShelf {
            return Biquad(
                b0: amplitude * ((amplitude + 1) + (amplitude - 1) * cosine + beta),
                b1: -2 * amplitude * ((amplitude - 1) + (amplitude + 1) * cosine),
                b2: amplitude * ((amplitude + 1) + (amplitude - 1) * cosine - beta),
                a0: (amplitude + 1) - (amplitude - 1) * cosine + beta,
                a1: 2 * ((amplitude - 1) - (amplitude + 1) * cosine),
                a2: (amplitude + 1) - (amplitude - 1) * cosine - beta
            )
        }

        return Biquad(
            b0: amplitude * ((amplitude + 1) - (amplitude - 1) * cosine + beta),
            b1: 2 * amplitude * ((amplitude - 1) - (amplitude + 1) * cosine),
            b2: amplitude * ((amplitude + 1) - (amplitude - 1) * cosine - beta),
            a0: (amplitude + 1) + (amplitude - 1) * cosine + beta,
            a1: -2 * ((amplitude - 1) + (amplitude + 1) * cosine),
            a2: (amplitude + 1) + (amplitude - 1) * cosine - beta
        )
    }
}

private nonisolated func dbToLinear(_ db: Double) -> Double {
    pow(10, db / 20)
}

private nonisolated func linearToDB(_ value: Double) -> Double {
    20 * log10(max(value, 0.000_001))
}
