import Foundation

public struct TrackerModule: Sendable, Equatable {
    public var format: TrackerFormat
    public var title: String
    public var channelCount: Int
    public var orders: [Int]
    public var patterns: [TrackerPattern]
    public var samples: [TrackerSample]
    public var instruments: [TrackerInstrument]
    public var initialSpeed: Int
    public var initialTempo: Int
    public var globalVolume: Double

    public init(
        format: TrackerFormat,
        title: String,
        channelCount: Int,
        orders: [Int],
        patterns: [TrackerPattern],
        samples: [TrackerSample],
        instruments: [TrackerInstrument] = [],
        initialSpeed: Int = 6,
        initialTempo: Int = 125,
        globalVolume: Double = 1
    ) {
        self.format = format
        self.title = title
        self.channelCount = channelCount
        self.orders = orders
        self.patterns = patterns
        self.samples = samples
        self.instruments = instruments.isEmpty ? Self.defaultInstruments(for: samples) : instruments
        self.initialSpeed = max(1, initialSpeed)
        self.initialTempo = max(32, initialTempo)
        self.globalVolume = globalVolume
    }

    private static func defaultInstruments(for samples: [TrackerSample]) -> [TrackerInstrument] {
        samples.indices.map { sampleIndex in
            TrackerInstrument(
                name: samples[sampleIndex].name,
                sampleMap: Array(repeating: sampleIndex, count: 96)
            )
        }
    }
}

public struct TrackerPattern: Sendable, Equatable {
    public var rowCount: Int
    public var channelCount: Int
    public var events: [TrackerEvent]

    public init(rowCount: Int, channelCount: Int, events: [TrackerEvent]) {
        self.rowCount = rowCount
        self.channelCount = channelCount
        self.events = events
    }

    public subscript(row: Int, channel: Int) -> TrackerEvent {
        events[row * channelCount + channel]
    }
}

public struct TrackerEvent: Sendable, Equatable {
    public var pitch: TrackerPitch?
    public var instrument: Int?
    public var volume: Int?
    public var command: TrackerCommand

    public init(
        pitch: TrackerPitch? = nil,
        instrument: Int? = nil,
        volume: Int? = nil,
        command: TrackerCommand = .none
    ) {
        self.pitch = pitch
        self.instrument = instrument
        self.volume = volume
        self.command = command
    }

    public static let empty = TrackerEvent()
}

public enum TrackerPitch: Sendable, Equatable {
    case midi(Int)
    case amigaPeriod(Int)
    case keyOff
}

public enum TrackerCommand: Sendable, Equatable {
    case none
    case arpeggio(x: Int, y: Int)
    case portamentoUp(Int)
    case portamentoDown(Int)
    case tonePortamento(Int)
    case vibrato(speed: Int, depth: Int)
    case tonePortamentoVolumeSlide(portamento: Int, up: Int, down: Int)
    case vibratoVolumeSlide(speed: Int, depth: Int, up: Int, down: Int)
    case tremolo(speed: Int, depth: Int)
    case volumeSlide(up: Int, down: Int)
    case panning(Double)
    case panningSlide(left: Int, right: Int)
    case setSpeed(Int)
    case setTempo(Int)
    case setVolume(Int)
    case setGlobalVolume(Int)
    case globalVolumeSlide(up: Int, down: Int)
    case sampleOffset(Int)
    case positionJump(Int)
    case patternBreak(Int)
    case finePortamentoUp(Int)
    case finePortamentoDown(Int)
    case fineVolumeUp(Int)
    case fineVolumeDown(Int)
    case retrigger(interval: Int)
    case noteCut(tick: Int)
    case noteDelay(tick: Int)
    case patternDelay(rows: Int)
    case raw(effect: Int, parameter: Int)
}

public struct RenderOptions: Sendable, Equatable {
    public var spatialization: SpatializationMode
    public var gain: Double

    public init(spatialization: SpatializationMode = .stereo, gain: Double = 1) {
        self.spatialization = spatialization
        self.gain = gain
    }

    public static let `default` = RenderOptions()
}

public enum SpatializationMode: Sendable, Equatable {
    case stereo
    case psychoacoustic3D(Psychoacoustic3DOptions)
}

public struct Psychoacoustic3DOptions: Sendable, Equatable {
    public var stageWidthDegrees: Double
    public var maxInterauralDelayMicroseconds: Double
    public var headShadow: Double
    public var earlyReflectionLevel: Double
    public var crossfeed: Double

    public init(
        stageWidthDegrees: Double = 82,
        maxInterauralDelayMicroseconds: Double = 690,
        headShadow: Double = 0.34,
        earlyReflectionLevel: Double = 0.08,
        crossfeed: Double = 0.08
    ) {
        self.stageWidthDegrees = stageWidthDegrees
        self.maxInterauralDelayMicroseconds = maxInterauralDelayMicroseconds
        self.headShadow = max(0, min(0.95, headShadow))
        self.earlyReflectionLevel = max(0, min(0.35, earlyReflectionLevel))
        self.crossfeed = max(0, min(0.35, crossfeed))
    }

    public static let spacious = Psychoacoustic3DOptions()
}

public enum SampleLoopMode: Sendable, Equatable {
    case none
    case forward
    case pingPong
}

public struct TrackerInstrument: Sendable, Equatable {
    public var name: String
    public var sampleMap: [Int?]
    public var volumeEnvelope: TrackerEnvelope
    public var panningEnvelope: TrackerEnvelope

    public init(
        name: String,
        sampleMap: [Int?],
        volumeEnvelope: TrackerEnvelope = .disabled,
        panningEnvelope: TrackerEnvelope = .disabled
    ) {
        self.name = name
        let normalized = Array(sampleMap.prefix(96))
        self.sampleMap = normalized + Array(repeating: nil, count: max(0, 96 - normalized.count))
        self.volumeEnvelope = volumeEnvelope
        self.panningEnvelope = panningEnvelope
    }

    public func sampleIndex(for pitch: TrackerPitch?) -> Int? {
        guard let pitch else { return sampleMap.first ?? nil }
        let key = switch pitch {
        case let .midi(note):
            max(0, min(95, note - 12))
        case .amigaPeriod, .keyOff:
            0
        }
        return sampleMap[key]
    }

    public func remappingSamples(_ transform: (Int) -> Int) -> TrackerInstrument {
        TrackerInstrument(
            name: name,
            sampleMap: sampleMap.map { $0.map(transform) },
            volumeEnvelope: volumeEnvelope,
            panningEnvelope: panningEnvelope
        )
    }
}

public struct TrackerEnvelope: Sendable, Equatable {
    public var points: [TrackerEnvelopePoint]
    public var enabled: Bool
    public var sustainEnabled: Bool
    public var loopEnabled: Bool
    public var sustainPoint: Int
    public var loopStartPoint: Int
    public var loopEndPoint: Int

    public init(
        points: [TrackerEnvelopePoint],
        enabled: Bool = true,
        sustainEnabled: Bool = false,
        loopEnabled: Bool = false,
        sustainPoint: Int = 0,
        loopStartPoint: Int = 0,
        loopEndPoint: Int = 0
    ) {
        self.points = points.sorted { $0.tick < $1.tick }
        self.enabled = enabled
        self.sustainEnabled = sustainEnabled
        self.loopEnabled = loopEnabled
        self.sustainPoint = sustainPoint
        self.loopStartPoint = loopStartPoint
        self.loopEndPoint = loopEndPoint
    }

    public static let disabled = TrackerEnvelope(points: [], enabled: false)

    public func value(at tick: Int) -> Double? {
        guard enabled, !points.isEmpty else { return nil }
        if tick <= points[0].tick {
            return points[0].value
        }

        for index in 0..<points.count - 1 {
            let start = points[index]
            let end = points[index + 1]
            guard tick <= end.tick else { continue }
            let distance = max(1, end.tick - start.tick)
            let t = Double(tick - start.tick) / Double(distance)
            return start.value + (end.value - start.value) * t
        }

        return points.last?.value
    }

    public func nextTick(after tick: Int, keyReleased: Bool) -> Int {
        guard enabled, !points.isEmpty else { return tick }

        if sustainEnabled,
           !keyReleased,
           points.indices.contains(sustainPoint),
           tick >= points[sustainPoint].tick {
            return points[sustainPoint].tick
        }

        if loopEnabled,
           points.indices.contains(loopStartPoint),
           points.indices.contains(loopEndPoint),
           loopEndPoint >= loopStartPoint {
            let start = points[loopStartPoint].tick
            let end = points[loopEndPoint].tick
            if end > start, tick >= end {
                return start + (tick - end)
            }
        }

        return tick + 1
    }
}

public struct TrackerEnvelopePoint: Sendable, Equatable {
    public var tick: Int
    public var value: Double

    public init(tick: Int, value: Double) {
        self.tick = max(0, tick)
        self.value = max(0, min(1, value))
    }
}

public struct TrackerSample: Sendable, Equatable {
    public var name: String
    public var pcm: [Float]
    public var volume: Double
    public var panning: Double
    public var c2Rate: Double
    public var relativeNote: Int
    public var finetuneCents: Double
    public var loopStart: Int
    public var loopLength: Int
    public var loopMode: SampleLoopMode

    public init(
        name: String,
        pcm: [Float],
        volume: Double = 1,
        panning: Double = 0.5,
        c2Rate: Double = 8_363,
        relativeNote: Int = 0,
        finetuneCents: Double = 0,
        loopStart: Int = 0,
        loopLength: Int = 0,
        loopMode: SampleLoopMode = .none
    ) {
        self.name = name
        self.pcm = pcm
        self.volume = max(0, min(1, volume))
        self.panning = max(0, min(1, panning))
        self.c2Rate = c2Rate > 0 ? c2Rate : 8_363
        self.relativeNote = relativeNote
        self.finetuneCents = finetuneCents
        self.loopStart = max(0, loopStart)
        self.loopLength = max(0, loopLength)
        self.loopMode = loopMode
    }

    public static let empty = TrackerSample(name: "", pcm: [])

    public var loopEnd: Int {
        min(pcm.count, loopStart + loopLength)
    }
}

public struct PCMBuffer: Sendable, Equatable {
    public var sampleRate: Int
    public var channelCount: Int
    public var interleavedSamples: [Float]

    public init(sampleRate: Int, channelCount: Int, interleavedSamples: [Float]) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.interleavedSamples = interleavedSamples
    }

    public var frameCount: Int {
        guard channelCount > 0 else { return 0 }
        return interleavedSamples.count / channelCount
    }
}
