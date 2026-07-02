import Foundation

public final class ModuleRenderer {
    public let module: TrackerModule
    public let sampleRate: Int
    public let options: RenderOptions

    private var orderIndex = 0
    private var rowIndex = 0
    private var speed: Int
    private var tempo: Int
    private var globalVolume: Double
    private var framesRemainingInTick = 0
    private var ticksRemainingInRow = 0
    private var tickIndex = 0
    private var voices: [Voice]
    private var spatialMixer: SpatialMixer
    private var pendingJump: Int?
    private var pendingBreakRow: Int?
    private var pendingPatternDelayRows = 0

    public init(
        module: TrackerModule,
        sampleRate: Int = 44_100,
        options: RenderOptions = .default
    ) {
        self.module = module
        self.sampleRate = sampleRate
        self.options = options
        self.speed = module.initialSpeed
        self.tempo = module.initialTempo
        self.globalVolume = module.globalVolume
        self.voices = (0..<module.channelCount).map { Voice(defaultPan: Self.defaultPan(for: $0)) }
        self.spatialMixer = SpatialMixer(
            mode: options.spatialization,
            sampleRate: sampleRate,
            voiceCount: module.channelCount
        )
    }

    public func reset() {
        orderIndex = 0
        rowIndex = 0
        speed = module.initialSpeed
        tempo = module.initialTempo
        globalVolume = module.globalVolume
        framesRemainingInTick = 0
        ticksRemainingInRow = 0
        tickIndex = 0
        pendingJump = nil
        pendingBreakRow = nil
        pendingPatternDelayRows = 0
        voices = (0..<module.channelCount).map { Voice(defaultPan: Self.defaultPan(for: $0)) }
        spatialMixer = SpatialMixer(
            mode: options.spatialization,
            sampleRate: sampleRate,
            voiceCount: module.channelCount
        )
    }

    public func render(seconds: Double) -> PCMBuffer {
        render(frameCount: max(0, Int((seconds * Double(sampleRate)).rounded())))
    }

    public func render(frameCount: Int) -> PCMBuffer {
        guard frameCount > 0 else {
            return PCMBuffer(sampleRate: sampleRate, channelCount: 2, interleavedSamples: [])
        }

        var output = Array(repeating: Float(0), count: frameCount * 2)
        var renderedFrames = 0

        while renderedFrames < frameCount {
            if ticksRemainingInRow <= 0 {
                processCurrentRow()
                ticksRemainingInRow = max(1, speed * (1 + pendingPatternDelayRows))
                pendingPatternDelayRows = 0
                tickIndex = 0
            }

            if framesRemainingInTick <= 0 {
                if tickIndex > 0 {
                    processTickEffects(tick: tickIndex % max(1, speed))
                }
                framesRemainingInTick = tickFrameCount()
            }

            let chunk = min(framesRemainingInTick, frameCount - renderedFrames)
            renderFrames(count: chunk, into: &output, startingAt: renderedFrames)
            framesRemainingInTick -= chunk
            renderedFrames += chunk

            if framesRemainingInTick <= 0 {
                tickIndex += 1
                ticksRemainingInRow -= 1

                if ticksRemainingInRow <= 0 {
                    advanceRow()
                }
            }
        }

        return PCMBuffer(sampleRate: sampleRate, channelCount: 2, interleavedSamples: output)
    }

    private func processCurrentRow() {
        pendingJump = nil
        pendingBreakRow = nil
        pendingPatternDelayRows = 0
        voices.indices.forEach { voices[$0].beginRow() }
        guard let pattern = currentPattern() else { return }
        rowIndex = min(rowIndex, pattern.rowCount - 1)

        for channel in 0..<min(module.channelCount, pattern.channelCount) {
            let event = pattern[rowIndex, channel]
            applyGlobalCommand(event.command)
            apply(event: event, to: channel)
        }
    }

    private func processTickEffects(tick: Int) {
        applyGlobalSlides()

        for channel in voices.indices {
            if let delayed = voices[channel].delayedEvent,
               tick == voices[channel].noteDelayTick {
                voices[channel].delayedEvent = nil
                trigger(event: delayed, to: channel, sampleOffset: 0, allowsTonePortamento: false)
            }

            if voices[channel].noteCutTick == tick {
                voices[channel].active = false
            }

            guard voices[channel].active else { continue }

            applyPitchEffects(to: channel, tick: tick)
            applyVolumeAndPanEffects(to: channel)
            advanceEnvelopes(channel: channel)

            let retrigger = voices[channel].retriggerInterval
            if retrigger > 0, tick > 0, tick.isMultiple(of: retrigger) {
                voices[channel].position = 0
                voices[channel].direction = 1
            }
        }
    }

    private func apply(event: TrackerEvent, to channel: Int) {
        guard voices.indices.contains(channel) else { return }

        let command = event.command
        configureEffect(command, channel: channel)

        if case let .noteDelay(tick) = command {
            var delayed = event
            delayed.command = .none
            voices[channel].delayedEvent = delayed
            voices[channel].noteDelayTick = tick
            return
        }

        let sampleOffset = sampleOffset(from: command)
        let allowsTonePortamento = command.isTonePortamentoFamily
        trigger(event: event, to: channel, sampleOffset: sampleOffset, allowsTonePortamento: allowsTonePortamento)
    }

    private func trigger(
        event: TrackerEvent,
        to channel: Int,
        sampleOffset: Int,
        allowsTonePortamento: Bool
    ) {
        guard voices.indices.contains(channel) else { return }

        if case .keyOff = event.pitch {
            if voices[channel].volumeEnvelope.enabled {
                voices[channel].keyReleased = true
            } else {
                voices[channel].active = false
            }
            return
        }

        if let instrument = event.instrument {
            voices[channel].instrumentIndex = instrument - 1
        }

        guard let pitch = event.pitch else { return }
        guard let sampleIndex = resolvedSampleIndex(for: channel, pitch: pitch),
              module.samples.indices.contains(sampleIndex) else { return }

        let sample = module.samples[sampleIndex]
        guard !sample.pcm.isEmpty else { return }
        let newStep = playbackStep(for: pitch, sample: sample)

        if allowsTonePortamento, voices[channel].active {
            voices[channel].targetStep = newStep
            return
        }

        voices[channel].sampleIndex = sampleIndex
        voices[channel].volume = sample.volume
        voices[channel].currentVolume = sample.volume
        voices[channel].pan = sample.panning == 0.5 ? voices[channel].defaultPan : sample.panning
        configureInstrumentEnvelopes(channel: channel)
        if let volume = event.volume {
            voices[channel].volume = Double(max(0, min(64, volume))) / 64
            voices[channel].currentVolume = voices[channel].volume
        }
        voices[channel].baseStep = newStep
        voices[channel].step = newStep
        voices[channel].targetStep = nil
        voices[channel].position = Double(max(0, sampleOffset))
        voices[channel].direction = 1
        voices[channel].active = true
        voices[channel].keyReleased = false
    }

    private func configureEffect(_ command: TrackerCommand, channel: Int) {
        guard voices.indices.contains(channel) else { return }

        switch command {
        case let .arpeggio(x, y):
            voices[channel].arpeggio = (x, y)
        case let .portamentoUp(amount):
            voices[channel].portamentoUp = remembered(amount, replacing: &voices[channel].lastPortamentoUp)
        case let .portamentoDown(amount):
            voices[channel].portamentoDown = remembered(amount, replacing: &voices[channel].lastPortamentoDown)
        case let .tonePortamento(amount):
            voices[channel].tonePortamentoSpeed = remembered(amount, replacing: &voices[channel].lastTonePortamento)
        case let .vibrato(speed, depth):
            setVibrato(channel: channel, speed: speed, depth: depth)
        case let .vibratoVolumeSlide(speed, depth, up, down):
            setVibrato(channel: channel, speed: speed, depth: depth)
            setVolumeSlide(channel: channel, up: up, down: down)
        case let .tonePortamentoVolumeSlide(portamento, up, down):
            if portamento > 0 {
                voices[channel].tonePortamentoSpeed = remembered(portamento, replacing: &voices[channel].lastTonePortamento)
            } else {
                voices[channel].tonePortamentoSpeed = voices[channel].lastTonePortamento
            }
            setVolumeSlide(channel: channel, up: up, down: down)
        case let .tremolo(speed, depth):
            setTremolo(channel: channel, speed: speed, depth: depth)
        case let .volumeSlide(up, down):
            setVolumeSlide(channel: channel, up: up, down: down)
        case let .panning(value):
            voices[channel].pan = max(0, min(1, value))
        case let .panningSlide(left, right):
            voices[channel].panningSlideLeft = left
            voices[channel].panningSlideRight = right
        case let .setVolume(volume):
            voices[channel].volume = Double(max(0, min(64, volume))) / 64
            voices[channel].currentVolume = voices[channel].volume
        case let .finePortamentoUp(amount):
            slideBaseStep(channel: channel, semitones: Double(amount) / 64)
        case let .finePortamentoDown(amount):
            slideBaseStep(channel: channel, semitones: -Double(amount) / 64)
        case let .fineVolumeUp(amount):
            voices[channel].volume = min(1, voices[channel].volume + Double(amount) / 64)
            voices[channel].currentVolume = voices[channel].volume
        case let .fineVolumeDown(amount):
            voices[channel].volume = max(0, voices[channel].volume - Double(amount) / 64)
            voices[channel].currentVolume = voices[channel].volume
        case let .retrigger(interval):
            voices[channel].retriggerInterval = interval
        case let .noteCut(tick):
            voices[channel].noteCutTick = tick
        default:
            break
        }
    }

    private func applyGlobalCommand(_ command: TrackerCommand) {
        switch command {
        case let .setSpeed(value):
            speed = max(1, min(255, value))
        case let .setTempo(value):
            tempo = max(32, min(255, value))
        case let .setGlobalVolume(value):
            globalVolume = Double(max(0, min(128, value))) / 128
        case let .globalVolumeSlide(up, down):
            voices.indices.forEach {
                voices[$0].globalVolumeSlideUp = up
                voices[$0].globalVolumeSlideDown = down
            }
        case let .positionJump(order):
            pendingJump = max(0, order)
            pendingBreakRow = 0
        case let .patternBreak(row):
            pendingBreakRow = max(0, row)
        case let .patternDelay(rows):
            pendingPatternDelayRows = max(pendingPatternDelayRows, rows)
        default:
            break
        }
    }

    private func applyPitchEffects(to channel: Int, tick: Int) {
        if voices[channel].portamentoUp > 0 {
            slideBaseStep(channel: channel, semitones: Double(voices[channel].portamentoUp) / 384)
        }

        if voices[channel].portamentoDown > 0 {
            slideBaseStep(channel: channel, semitones: -Double(voices[channel].portamentoDown) / 384)
        }

        if let target = voices[channel].targetStep {
            let speed = max(1, voices[channel].tonePortamentoSpeed)
            let distance = abs(target - voices[channel].baseStep)
            let delta = max(distance * 0.018, voices[channel].baseStep * Double(speed) / 16_384)
            if voices[channel].baseStep < target {
                voices[channel].baseStep = min(target, voices[channel].baseStep + delta)
            } else {
                voices[channel].baseStep = max(target, voices[channel].baseStep - delta)
            }
        }

        var step = voices[channel].baseStep

        if let arpeggio = voices[channel].arpeggio {
            let semitone = switch tick % 3 {
            case 1: arpeggio.x
            case 2: arpeggio.y
            default: 0
            }
            step *= pow(2, Double(semitone) / 12)
        }

        if voices[channel].vibratoDepth > 0 {
            let cents = sin(voices[channel].vibratoPhase) * Double(voices[channel].vibratoDepth) * 6.25
            step *= pow(2, cents / 1_200)
            voices[channel].vibratoPhase += max(1, Double(voices[channel].vibratoSpeed)) * .pi / 32
        }

        voices[channel].step = step
    }

    private func applyVolumeAndPanEffects(to channel: Int) {
        let volumeDelta = Double(voices[channel].volumeSlideUp - voices[channel].volumeSlideDown) / 64
        if volumeDelta != 0 {
            voices[channel].volume = max(0, min(1, voices[channel].volume + volumeDelta))
        }

        let panDelta = Double(voices[channel].panningSlideRight - voices[channel].panningSlideLeft) / 64
        if panDelta != 0 {
            voices[channel].pan = max(0, min(1, voices[channel].pan + panDelta))
        }

        var volume = voices[channel].volume
        if voices[channel].tremoloDepth > 0 {
            volume += sin(voices[channel].tremoloPhase) * Double(voices[channel].tremoloDepth) / 64
            voices[channel].tremoloPhase += max(1, Double(voices[channel].tremoloSpeed)) * .pi / 32
        }
        voices[channel].currentVolume = max(0, min(1, volume))
    }

    private func applyGlobalSlides() {
        let up = voices.map(\.globalVolumeSlideUp).max() ?? 0
        let down = voices.map(\.globalVolumeSlideDown).max() ?? 0
        let delta = Double(up - down) / 128
        if delta != 0 {
            globalVolume = max(0, min(1, globalVolume + delta))
        }
    }

    private func advanceEnvelopes(channel: Int) {
        voices[channel].volumeEnvelopeTick = voices[channel].volumeEnvelope.nextTick(
            after: voices[channel].volumeEnvelopeTick,
            keyReleased: voices[channel].keyReleased
        )
        voices[channel].panningEnvelopeTick = voices[channel].panningEnvelope.nextTick(
            after: voices[channel].panningEnvelopeTick,
            keyReleased: voices[channel].keyReleased
        )

        if voices[channel].keyReleased,
           voices[channel].volumeEnvelope.enabled,
           let value = voices[channel].volumeEnvelope.value(at: voices[channel].volumeEnvelopeTick),
           value <= 0.0001 {
            voices[channel].active = false
        }
    }

    private func renderFrames(count: Int, into output: inout [Float], startingAt startFrame: Int) {
        guard count > 0 else { return }

        for frameOffset in 0..<count {
            var left = 0.0
            var right = 0.0

            for channel in voices.indices {
                guard voices[channel].active,
                      let sampleIndex = voices[channel].sampleIndex,
                      module.samples.indices.contains(sampleIndex) else { continue }

                let sample = module.samples[sampleIndex]
                guard let value = sampleValue(sample: sample, voice: &voices[channel]) else { continue }
                let amplitude = value * voices[channel].currentVolume * envelopeVolume(channel: channel) * globalVolume * options.gain
                let mixed = spatialMixer.mix(mono: amplitude, pan: envelopePan(channel: channel), voiceIndex: channel)
                left += mixed.left
                right += mixed.right
            }

            let index = (startFrame + frameOffset) * 2
            output[index] = Float(softClip(left))
            output[index + 1] = Float(softClip(right))
        }
    }

    private func sampleValue(sample: TrackerSample, voice: inout Voice) -> Double? {
        guard voice.position >= 0 else {
            voice.active = false
            return nil
        }

        normalizeLoopPosition(sample: sample, voice: &voice)
        let index = Int(voice.position)
        guard sample.pcm.indices.contains(index) else {
            voice.active = false
            return nil
        }

        let nextIndex = min(index + 1, sample.pcm.count - 1)
        let fraction = voice.position - Double(index)
        let current = Double(sample.pcm[index])
        let next = Double(sample.pcm[nextIndex])
        voice.position += voice.step * Double(voice.direction)
        return current + (next - current) * fraction
    }

    private func normalizeLoopPosition(sample: TrackerSample, voice: inout Voice) {
        guard !sample.pcm.isEmpty else {
            voice.active = false
            return
        }

        switch sample.loopMode {
        case .none:
            if voice.position >= Double(sample.pcm.count) || voice.position < 0 {
                voice.active = false
            }
        case .forward:
            guard sample.loopLength > 1, sample.loopEnd > sample.loopStart else {
                if voice.position >= Double(sample.pcm.count) { voice.active = false }
                return
            }
            let loopStart = Double(sample.loopStart)
            let loopLength = Double(sample.loopEnd - sample.loopStart)
            if voice.position >= Double(sample.loopEnd) {
                voice.position = loopStart + (voice.position - loopStart).truncatingRemainder(dividingBy: loopLength)
            }
        case .pingPong:
            guard sample.loopLength > 1, sample.loopEnd > sample.loopStart else {
                if voice.position >= Double(sample.pcm.count) { voice.active = false }
                return
            }
            let start = Double(sample.loopStart)
            let end = Double(sample.loopEnd - 1)
            if voice.position > end {
                voice.position = end - (voice.position - end)
                voice.direction = -1
            } else if voice.position < start {
                voice.position = start + (start - voice.position)
                voice.direction = 1
            }
        }
    }

    private func advanceRow() {
        guard !module.orders.isEmpty else { return }
        if let jump = pendingJump {
            orderIndex = normalizedOrderIndex(jump)
            rowIndex = pendingBreakRow ?? 0
            return
        }

        if let breakRow = pendingBreakRow {
            orderIndex = normalizedOrderIndex(orderIndex + 1)
            rowIndex = breakRow
            return
        }

        guard let pattern = currentPattern() else {
            orderIndex = normalizedOrderIndex(orderIndex + 1)
            rowIndex = 0
            return
        }

        rowIndex += 1
        if rowIndex >= pattern.rowCount {
            rowIndex = 0
            orderIndex = normalizedOrderIndex(orderIndex + 1)
        }
    }

    private func currentPattern() -> TrackerPattern? {
        guard !module.patterns.isEmpty else { return nil }
        guard !module.orders.isEmpty else { return module.patterns.first }
        let normalized = normalizedOrderIndex(orderIndex)
        let patternIndex = module.orders[normalized]
        guard module.patterns.indices.contains(patternIndex) else { return module.patterns.first }
        return module.patterns[patternIndex]
    }

    private func normalizedOrderIndex(_ index: Int) -> Int {
        guard !module.orders.isEmpty else { return 0 }
        let count = module.orders.count
        return ((index % count) + count) % count
    }

    private func tickFrameCount() -> Int {
        let seconds = 2.5 / Double(max(32, tempo))
        return max(1, Int((seconds * Double(sampleRate)).rounded()))
    }

    private func playbackStep(for pitch: TrackerPitch, sample: TrackerSample) -> Double {
        switch pitch {
        case let .amigaPeriod(period):
            guard period > 0 else { return 0 }
            let amigaPALClock = 7_093_789.2
            let playbackRate = amigaPALClock / (2 * Double(period))
            return playbackRate / Double(sampleRate)
        case let .midi(note):
            let semitones = Double(note - 60 + sample.relativeNote) + sample.finetuneCents / 100
            let playbackRate = sample.c2Rate * pow(2, semitones / 12)
            return playbackRate / Double(sampleRate)
        case .keyOff:
            return 0
        }
    }

    private func resolvedSampleIndex(for channel: Int, pitch: TrackerPitch) -> Int? {
        if let instrumentIndex = voices[channel].instrumentIndex,
           module.instruments.indices.contains(instrumentIndex),
           let mapped = module.instruments[instrumentIndex].sampleIndex(for: pitch) {
            return mapped
        }

        return voices[channel].sampleIndex
    }

    private func configureInstrumentEnvelopes(channel: Int) {
        guard let instrumentIndex = voices[channel].instrumentIndex,
              module.instruments.indices.contains(instrumentIndex) else {
            voices[channel].volumeEnvelope = .disabled
            voices[channel].panningEnvelope = .disabled
            return
        }

        let instrument = module.instruments[instrumentIndex]
        voices[channel].volumeEnvelope = instrument.volumeEnvelope
        voices[channel].panningEnvelope = instrument.panningEnvelope
        voices[channel].volumeEnvelopeTick = 0
        voices[channel].panningEnvelopeTick = 0
    }

    private func envelopeVolume(channel: Int) -> Double {
        voices[channel].volumeEnvelope.value(at: voices[channel].volumeEnvelopeTick) ?? 1
    }

    private func envelopePan(channel: Int) -> Double {
        guard let envelopePan = voices[channel].panningEnvelope.value(at: voices[channel].panningEnvelopeTick) else {
            return voices[channel].pan
        }
        return max(0, min(1, voices[channel].pan + (envelopePan - 0.5)))
    }

    private func setVibrato(channel: Int, speed: Int, depth: Int) {
        if speed > 0 { voices[channel].lastVibratoSpeed = speed }
        if depth > 0 { voices[channel].lastVibratoDepth = depth }
        voices[channel].vibratoSpeed = voices[channel].lastVibratoSpeed
        voices[channel].vibratoDepth = voices[channel].lastVibratoDepth
    }

    private func setTremolo(channel: Int, speed: Int, depth: Int) {
        if speed > 0 { voices[channel].lastTremoloSpeed = speed }
        if depth > 0 { voices[channel].lastTremoloDepth = depth }
        voices[channel].tremoloSpeed = voices[channel].lastTremoloSpeed
        voices[channel].tremoloDepth = voices[channel].lastTremoloDepth
    }

    private func setVolumeSlide(channel: Int, up: Int, down: Int) {
        voices[channel].volumeSlideUp = up
        voices[channel].volumeSlideDown = down
    }

    private func slideBaseStep(channel: Int, semitones: Double) {
        let multiplier = pow(2, semitones / 12)
        voices[channel].baseStep = max(0, voices[channel].baseStep * multiplier)
        voices[channel].step = voices[channel].baseStep
    }

    private func remembered(_ value: Int, replacing memory: inout Int) -> Int {
        if value > 0 {
            memory = value
        }
        return memory
    }

    private func sampleOffset(from command: TrackerCommand) -> Int {
        if case let .sampleOffset(offset) = command {
            return offset
        }
        return 0
    }

    private static func defaultPan(for channel: Int) -> Double {
        let pattern = [0.18, 0.82, 0.82, 0.18]
        if channel < pattern.count {
            return pattern[channel]
        }
        return channel.isMultiple(of: 2) ? 0.28 : 0.72
    }
}

private extension TrackerCommand {
    var isTonePortamentoFamily: Bool {
        switch self {
        case .tonePortamento, .tonePortamentoVolumeSlide:
            return true
        default:
            return false
        }
    }
}

private struct Voice {
    var instrumentIndex: Int?
    var sampleIndex: Int?
    var position = 0.0
    var direction = 1
    var baseStep = 0.0
    var step = 0.0
    var targetStep: Double?
    var volume = 0.0
    var currentVolume = 0.0
    var pan: Double
    let defaultPan: Double
    var active = false
    var keyReleased = false
    var volumeEnvelope = TrackerEnvelope.disabled
    var panningEnvelope = TrackerEnvelope.disabled
    var volumeEnvelopeTick = 0
    var panningEnvelopeTick = 0

    var arpeggio: (x: Int, y: Int)?
    var portamentoUp = 0
    var portamentoDown = 0
    var tonePortamentoSpeed = 0
    var vibratoSpeed = 0
    var vibratoDepth = 0
    var vibratoPhase = 0.0
    var tremoloSpeed = 0
    var tremoloDepth = 0
    var tremoloPhase = 0.0
    var volumeSlideUp = 0
    var volumeSlideDown = 0
    var panningSlideLeft = 0
    var panningSlideRight = 0
    var globalVolumeSlideUp = 0
    var globalVolumeSlideDown = 0
    var retriggerInterval = 0
    var noteCutTick = -1
    var noteDelayTick = -1
    var delayedEvent: TrackerEvent?

    var lastPortamentoUp = 0
    var lastPortamentoDown = 0
    var lastTonePortamento = 0
    var lastVibratoSpeed = 0
    var lastVibratoDepth = 0
    var lastTremoloSpeed = 0
    var lastTremoloDepth = 0

    init(defaultPan: Double) {
        self.defaultPan = defaultPan
        self.pan = defaultPan
    }

    mutating func beginRow() {
        arpeggio = nil
        portamentoUp = 0
        portamentoDown = 0
        tonePortamentoSpeed = 0
        vibratoSpeed = 0
        vibratoDepth = 0
        tremoloSpeed = 0
        tremoloDepth = 0
        volumeSlideUp = 0
        volumeSlideDown = 0
        panningSlideLeft = 0
        panningSlideRight = 0
        globalVolumeSlideUp = 0
        globalVolumeSlideDown = 0
        retriggerInterval = 0
        noteCutTick = -1
        noteDelayTick = -1
        delayedEvent = nil
        currentVolume = volume
        step = baseStep
    }
}

private struct SpatialMixer {
    let mode: SpatializationMode
    let sampleRate: Int
    var states: [SpatialVoiceState]

    init(mode: SpatializationMode, sampleRate: Int, voiceCount: Int) {
        self.mode = mode
        self.sampleRate = sampleRate
        let maxDelayFrames = Int((0.030 * Double(sampleRate)).rounded()) + 2
        self.states = (0..<max(1, voiceCount)).map { _ in
            SpatialVoiceState(bufferLength: maxDelayFrames)
        }
    }

    mutating func mix(mono: Double, pan: Double, voiceIndex: Int) -> (left: Double, right: Double) {
        switch mode {
        case .stereo:
            let clampedPan = max(0, min(1, pan))
            return (
                mono * cos(clampedPan * .pi / 2),
                mono * sin(clampedPan * .pi / 2)
            )
        case let .psychoacoustic3D(options):
            return mixPsychoacoustic3D(mono: mono, pan: pan, voiceIndex: voiceIndex, options: options)
        }
    }

    private mutating func mixPsychoacoustic3D(
        mono: Double,
        pan: Double,
        voiceIndex: Int,
        options: Psychoacoustic3DOptions
    ) -> (left: Double, right: Double) {
        let stateIndex = min(max(0, voiceIndex), states.count - 1)
        let clampedPan = max(0, min(1, pan))
        let normalizedPan = clampedPan * 2 - 1
        let widthRadians = options.stageWidthDegrees * .pi / 180
        let azimuth = normalizedPan * widthRadians
        let side = sin(azimuth)
        let sideAmount = abs(side)
        let maxITDFrames = options.maxInterauralDelayMicroseconds * 0.000_001 * Double(sampleRate)
        let farDelay = Int((sideAmount * maxITDFrames).rounded())
        let reflectionDelay = Int((0.011 + Double((voiceIndex % 5)) * 0.003) * Double(sampleRate))

        let farSample = states[stateIndex].read(delayFrames: farDelay)
        let reflection = states[stateIndex].read(delayFrames: reflectionDelay)
        states[stateIndex].write(mono)

        let distance = 0.86 + Double((voiceIndex % 7)) * 0.035
        let nearGain = 1 / distance
        let farGain = nearGain * (1 - options.headShadow * sideAmount)
        let farFiltered = states[stateIndex].lowpass(farSample, amount: 0.26 + sideAmount * 0.28)
        let center = mono * (1 - sideAmount) * 0.18
        var left: Double
        var right: Double

        if side < 0 {
            left = mono * nearGain + center
            right = farFiltered * farGain + center
        } else {
            left = farFiltered * farGain + center
            right = mono * nearGain + center
        }

        let reflectionGain = options.earlyReflectionLevel * (0.6 + sideAmount * 0.4)
        left += reflection * reflectionGain * (side >= 0 ? 0.85 : 0.35)
        right += reflection * reflectionGain * (side < 0 ? 0.85 : 0.35)

        let crossfeed = options.crossfeed
        return (
            left: left * (1 - crossfeed) + right * crossfeed,
            right: right * (1 - crossfeed) + left * crossfeed
        )
    }
}

private struct SpatialVoiceState {
    var buffer: [Double]
    var writeIndex = 0
    var lowpassState = 0.0

    init(bufferLength: Int) {
        buffer = Array(repeating: 0, count: max(2, bufferLength))
    }

    func read(delayFrames: Int) -> Double {
        let delay = max(0, min(delayFrames, buffer.count - 1))
        let index = (writeIndex - delay + buffer.count) % buffer.count
        return buffer[index]
    }

    mutating func write(_ sample: Double) {
        buffer[writeIndex] = sample
        writeIndex = (writeIndex + 1) % buffer.count
    }

    mutating func lowpass(_ sample: Double, amount: Double) -> Double {
        let coefficient = max(0.02, min(0.98, amount))
        lowpassState += (sample - lowpassState) * coefficient
        return lowpassState
    }
}

private func softClip(_ value: Double) -> Double {
    tanh(value * 1.1)
}
