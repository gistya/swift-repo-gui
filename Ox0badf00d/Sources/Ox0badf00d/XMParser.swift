import Foundation

struct XMParser {
    let data: Data

    func parse() throws -> TrackerModule {
        var reader = BinaryReader(data: data)
        let signature = try reader.readString(length: 17)
        guard signature == "Extended Module:" else {
            throw ModuleError.invalidFormat("missing XM signature")
        }

        let title = try reader.readString(length: 20)
        try reader.skip(1)
        try reader.skip(20)
        try reader.skip(2)

        let headerStart = reader.offset
        let headerSize = Int(try reader.readUInt32LE())
        let songLength = Int(try reader.readUInt16LE())
        try reader.skip(2)
        let channelCount = Int(try reader.readUInt16LE())
        let patternCount = Int(try reader.readUInt16LE())
        let instrumentCount = Int(try reader.readUInt16LE())
        try reader.skip(2)
        let defaultSpeed = Int(try reader.readUInt16LE())
        let defaultTempo = Int(try reader.readUInt16LE())
        let orders = try reader.readBytes(256)
            .prefix(songLength)
            .map(Int.init)
            .filter { $0 < patternCount }
        try reader.seek(headerStart + headerSize)

        var patterns: [TrackerPattern] = []
        for _ in 0..<patternCount {
            patterns.append(try parsePattern(reader: &reader, channelCount: channelCount))
        }

        var samples: [TrackerSample] = []
        var instruments: [TrackerInstrument] = []
        for instrumentIndex in 0..<instrumentCount {
            let parsed = try parseInstrument(reader: &reader, fallbackName: "Instrument \(instrumentIndex + 1)")
            let baseSampleIndex = samples.count
            samples.append(contentsOf: parsed.samples)
            instruments.append(parsed.instrument.remappingSamples { baseSampleIndex + $0 })
        }

        return TrackerModule(
            format: .xm,
            title: title,
            channelCount: channelCount,
            orders: orders.isEmpty ? [0] : orders,
            patterns: patterns,
            samples: samples,
            instruments: instruments,
            initialSpeed: defaultSpeed,
            initialTempo: defaultTempo,
            globalVolume: 0.88
        )
    }

    private func parsePattern(reader: inout BinaryReader, channelCount: Int) throws -> TrackerPattern {
        let headerStart = reader.offset
        let headerSize = Int(try reader.readUInt32LE())
        try reader.skip(1)
        let rowCount = max(1, Int(try reader.readUInt16LE()))
        let packedSize = Int(try reader.readUInt16LE())
        try reader.seek(headerStart + headerSize)

        var events = Array(
            repeating: TrackerEvent.empty,
            count: rowCount * channelCount
        )

        guard packedSize > 0 else {
            return TrackerPattern(rowCount: rowCount, channelCount: channelCount, events: events)
        }

        let patternEnd = reader.offset + packedSize
        for row in 0..<rowCount {
            for channel in 0..<channelCount {
                guard reader.offset < patternEnd else { break }
                let first = Int(try reader.readUInt8())
                var note = 0
                var instrument = 0
                var volumeColumn = 0
                var effect = 0
                var parameter = 0

                if first & 0x80 != 0 {
                    if first & 0x01 != 0 { note = Int(try reader.readUInt8()) }
                    if first & 0x02 != 0 { instrument = Int(try reader.readUInt8()) }
                    if first & 0x04 != 0 { volumeColumn = Int(try reader.readUInt8()) }
                    if first & 0x08 != 0 { effect = Int(try reader.readUInt8()) }
                    if first & 0x10 != 0 { parameter = Int(try reader.readUInt8()) }
                } else {
                    note = first
                    instrument = Int(try reader.readUInt8())
                    volumeColumn = Int(try reader.readUInt8())
                    effect = Int(try reader.readUInt8())
                    parameter = Int(try reader.readUInt8())
                }

                events[row * channelCount + channel] = TrackerEvent(
                    pitch: Self.pitch(fromXMNote: note),
                    instrument: instrument > 0 ? instrument : nil,
                    volume: Self.volume(fromXMVolumeColumn: volumeColumn),
                    command: Self.command(effect: effect, parameter: parameter)
                )
            }
        }

        try reader.seek(patternEnd)
        return TrackerPattern(rowCount: rowCount, channelCount: channelCount, events: events)
    }

    private func parseInstrument(reader: inout BinaryReader, fallbackName: String) throws -> ParsedXMInstrument {
        let headerStart = reader.offset
        let headerSize = Int(try reader.readUInt32LE())
        let headerEnd = headerStart + headerSize
        let name = try reader.readString(length: 22)
        try reader.skip(1)
        let sampleCount = Int(try reader.readUInt16LE())

        guard sampleCount > 0 else {
            try reader.seek(headerEnd)
            return ParsedXMInstrument(
                instrument: TrackerInstrument(
                    name: name.isEmpty ? fallbackName : name,
                    sampleMap: Array(repeating: nil, count: 96)
                ),
                samples: []
            )
        }

        let sampleHeaderSize = Int(try reader.readUInt32LE())
        let keyMap = try reader.readBytes(96).map(Int.init)
        let volumeEnvelopePoints = try parseEnvelopePoints(reader: &reader, scale: 64)
        let panningEnvelopePoints = try parseEnvelopePoints(reader: &reader, scale: 64)
        let volumePointCount = Int(try reader.readUInt8())
        let panningPointCount = Int(try reader.readUInt8())
        let volumeSustainPoint = Int(try reader.readUInt8())
        let volumeLoopStartPoint = Int(try reader.readUInt8())
        let volumeLoopEndPoint = Int(try reader.readUInt8())
        let panningSustainPoint = Int(try reader.readUInt8())
        let panningLoopStartPoint = Int(try reader.readUInt8())
        let panningLoopEndPoint = Int(try reader.readUInt8())
        let volumeType = Int(try reader.readUInt8())
        let panningType = Int(try reader.readUInt8())

        try reader.seek(headerEnd)

        var headers: [XMSampleHeader] = []
        for sampleIndex in 0..<sampleCount {
            headers.append(try parseSampleHeader(
                reader: &reader,
                headerSize: sampleHeaderSize,
                fallbackName: "\(name.isEmpty ? fallbackName : name) \(sampleIndex + 1)"
            ))
        }

        var decoded: [TrackerSample] = []
        for header in headers {
            decoded.append(try decodeSample(header: header, reader: &reader))
        }

        let sampleMap = keyMap.map { localIndex -> Int? in
            localIndex < sampleCount ? localIndex : nil
        }

        return ParsedXMInstrument(
            instrument: TrackerInstrument(
                name: name.isEmpty ? fallbackName : name,
                sampleMap: sampleMap,
                volumeEnvelope: envelope(
                    points: volumeEnvelopePoints,
                    count: volumePointCount,
                    type: volumeType,
                    sustainPoint: volumeSustainPoint,
                    loopStartPoint: volumeLoopStartPoint,
                    loopEndPoint: volumeLoopEndPoint
                ),
                panningEnvelope: envelope(
                    points: panningEnvelopePoints,
                    count: panningPointCount,
                    type: panningType,
                    sustainPoint: panningSustainPoint,
                    loopStartPoint: panningLoopStartPoint,
                    loopEndPoint: panningLoopEndPoint
                )
            ),
            samples: decoded
        )
    }

    private func parseEnvelopePoints(reader: inout BinaryReader, scale: Double) throws -> [TrackerEnvelopePoint] {
        try (0..<12).map { _ in
            let tick = Int(try reader.readUInt16LE())
            let value = Double(try reader.readUInt16LE()) / scale
            return TrackerEnvelopePoint(tick: tick, value: value)
        }
    }

    private func envelope(
        points: [TrackerEnvelopePoint],
        count: Int,
        type: Int,
        sustainPoint: Int,
        loopStartPoint: Int,
        loopEndPoint: Int
    ) -> TrackerEnvelope {
        let clampedCount = max(0, min(count, points.count))
        guard type & 0x01 != 0, clampedCount > 0 else { return .disabled }
        return TrackerEnvelope(
            points: Array(points.prefix(clampedCount)),
            enabled: true,
            sustainEnabled: type & 0x02 != 0,
            loopEnabled: type & 0x04 != 0,
            sustainPoint: sustainPoint,
            loopStartPoint: loopStartPoint,
            loopEndPoint: loopEndPoint
        )
    }

    private func parseSampleHeader(
        reader: inout BinaryReader,
        headerSize: Int,
        fallbackName: String
    ) throws -> XMSampleHeader {
        let start = reader.offset
        let length = Int(try reader.readUInt32LE())
        let loopStart = Int(try reader.readUInt32LE())
        let loopLength = Int(try reader.readUInt32LE())
        let volume = Int(try reader.readUInt8())
        let finetune = Int(try reader.readInt8())
        let type = Int(try reader.readUInt8())
        let panning = Int(try reader.readUInt8())
        let relativeNote = Int(try reader.readInt8())
        try reader.skip(1)
        let name = try reader.readString(length: 22)
        try reader.seek(start + max(headerSize, 40))

        return XMSampleHeader(
            name: name.isEmpty ? fallbackName : name,
            length: length,
            loopStart: loopStart,
            loopLength: loopLength,
            volume: volume,
            finetune: finetune,
            type: type,
            panning: panning,
            relativeNote: relativeNote
        )
    }

    private func decodeSample(header: XMSampleHeader, reader: inout BinaryReader) throws -> TrackerSample {
        guard header.length > 0 else {
            return TrackerSample.empty
        }

        let bytes = try reader.readBytes(header.length)
        let is16Bit = header.type & 0x10 != 0
        let pcm = is16Bit ? Self.decodeDelta16(bytes) : Self.decodeDelta8(bytes)
        let divisor = is16Bit ? 2 : 1
        let loopType = header.type & 0x03
        let loopMode: SampleLoopMode = loopType == 1 ? .forward : (loopType == 2 ? .pingPong : .none)

        return TrackerSample(
            name: header.name,
            pcm: pcm,
            volume: Double(min(64, header.volume)) / 64,
            panning: Double(header.panning) / 255,
            c2Rate: 8_363,
            relativeNote: header.relativeNote,
            finetuneCents: Double(header.finetune) * 100 / 128,
            loopStart: header.loopStart / divisor,
            loopLength: header.loopLength / divisor,
            loopMode: loopMode
        )
    }

    private static func pitch(fromXMNote note: Int) -> TrackerPitch? {
        switch note {
        case 1...96:
            return .midi(note + 11)
        case 97:
            return .keyOff
        default:
            return nil
        }
    }

    private static func volume(fromXMVolumeColumn value: Int) -> Int? {
        guard (0x10...0x50).contains(value) else { return nil }
        return value - 0x10
    }

    private static func command(effect: Int, parameter: Int) -> TrackerCommand {
        guard effect != 0 || parameter != 0 else { return .none }

        switch effect {
        case 0x00:
            return parameter > 0 ? .arpeggio(x: parameter >> 4, y: parameter & 0x0f) : .none
        case 0x01:
            return .portamentoUp(parameter)
        case 0x02:
            return .portamentoDown(parameter)
        case 0x03:
            return .tonePortamento(parameter)
        case 0x04:
            return .vibrato(speed: parameter >> 4, depth: parameter & 0x0f)
        case 0x05:
            return .tonePortamentoVolumeSlide(
                portamento: 0,
                up: parameter >> 4,
                down: parameter & 0x0f
            )
        case 0x06:
            return .vibratoVolumeSlide(
                speed: 0,
                depth: 0,
                up: parameter >> 4,
                down: parameter & 0x0f
            )
        case 0x07:
            return .tremolo(speed: parameter >> 4, depth: parameter & 0x0f)
        case 0x08:
            return .panning(Double(parameter) / 255)
        case 0x09:
            return .sampleOffset(parameter * 256)
        case 0x0a:
            return .volumeSlide(up: parameter >> 4, down: parameter & 0x0f)
        case 0x0b:
            return .positionJump(parameter)
        case 0x0c:
            return .setVolume(min(64, parameter))
        case 0x0d:
            let row = ((parameter >> 4) * 10) + (parameter & 0x0f)
            return .patternBreak(row)
        case 0x0f:
            guard parameter > 0 else { return .none }
            return parameter <= 31 ? .setSpeed(parameter) : .setTempo(parameter)
        case 0x10:
            return .setGlobalVolume(parameter)
        case 0x11:
            return .globalVolumeSlide(up: parameter >> 4, down: parameter & 0x0f)
        case 0x19:
            return .panningSlide(left: parameter & 0x0f, right: parameter >> 4)
        case 0x1b:
            return .retrigger(interval: parameter & 0x0f)
        case 0x0e:
            return extendedCommand(parameter: parameter)
        default:
            return .raw(effect: effect, parameter: parameter)
        }
    }

    private static func extendedCommand(parameter: Int) -> TrackerCommand {
        let subcommand = parameter >> 4
        let value = parameter & 0x0f

        switch subcommand {
        case 0x01:
            return .finePortamentoUp(value)
        case 0x02:
            return .finePortamentoDown(value)
        case 0x08:
            return .panning(Double(value) / 15)
        case 0x09:
            return .retrigger(interval: value)
        case 0x0a:
            return .fineVolumeUp(value)
        case 0x0b:
            return .fineVolumeDown(value)
        case 0x0c:
            return .noteCut(tick: value)
        case 0x0d:
            return .noteDelay(tick: value)
        case 0x0e:
            return .patternDelay(rows: value)
        default:
            return .raw(effect: 0x0e, parameter: parameter)
        }
    }

    private static func decodeDelta8(_ bytes: [UInt8]) -> [Float] {
        var accumulator = Int8(0)
        return bytes.map { byte in
            let delta = Int8(bitPattern: byte)
            accumulator = Int8(truncatingIfNeeded: Int(accumulator) + Int(delta))
            return Float(accumulator) / 128
        }
    }

    private static func decodeDelta16(_ bytes: [UInt8]) -> [Float] {
        var accumulator = Int16(0)
        var output: [Float] = []
        output.reserveCapacity(bytes.count / 2)

        var index = 0
        while index + 1 < bytes.count {
            let word = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
            let delta = Int16(bitPattern: word)
            accumulator = Int16(truncatingIfNeeded: Int(accumulator) + Int(delta))
            output.append(Float(accumulator) / 32_768)
            index += 2
        }

        return output
    }
}

private struct XMSampleHeader {
    let name: String
    let length: Int
    let loopStart: Int
    let loopLength: Int
    let volume: Int
    let finetune: Int
    let type: Int
    let panning: Int
    let relativeNote: Int
}

private struct ParsedXMInstrument {
    let instrument: TrackerInstrument
    let samples: [TrackerSample]
}
