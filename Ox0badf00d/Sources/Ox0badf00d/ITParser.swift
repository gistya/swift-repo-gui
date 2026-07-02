import Foundation

struct ITParser {
    let data: Data

    func parse() throws -> TrackerModule {
        var reader = BinaryReader(data: data)
        let signature = try reader.readString(length: 4)
        guard signature == "IMPM" else {
            throw ModuleError.invalidFormat("missing IT signature")
        }

        let title = try reader.readString(length: 26)
        try reader.skip(2)
        let orderCount = Int(try reader.readUInt16LE())
        let instrumentCount = Int(try reader.readUInt16LE())
        let sampleCount = Int(try reader.readUInt16LE())
        let patternCount = Int(try reader.readUInt16LE())
        try reader.skip(8)
        let globalVolume = Double(try reader.readUInt8()) / 128
        try reader.skip(1)
        let initialSpeed = Int(try reader.readUInt8())
        let initialTempo = Int(try reader.readUInt8())
        try reader.skip(10)
        try reader.skip(64)
        try reader.skip(64)

        let rawOrders = try reader.readBytes(orderCount)
        for _ in 0..<instrumentCount {
            try reader.skip(4)
        }
        let sampleOffsets = try (0..<sampleCount).map { _ in Int(try reader.readUInt32LE()) }
        let patternOffsets = try (0..<patternCount).map { _ in Int(try reader.readUInt32LE()) }

        let orders = rawOrders
            .prefix { $0 != 255 }
            .filter { $0 != 254 && Int($0) < patternCount }
            .map(Int.init)

        let samples = try sampleOffsets.map { try parseSample(at: $0) }
        var patterns: [TrackerPattern] = []
        var detectedChannels = 1
        for offset in patternOffsets {
            let parsed = try parsePattern(at: offset)
            patterns.append(parsed.pattern)
            detectedChannels = max(detectedChannels, parsed.usedChannels)
        }

        let channelCount = max(1, min(64, detectedChannels))
        let trimmedPatterns = patterns.map { pattern in
            trim(pattern: pattern, channelCount: channelCount)
        }

        return TrackerModule(
            format: .it,
            title: title,
            channelCount: channelCount,
            orders: orders.isEmpty ? [0] : orders,
            patterns: trimmedPatterns,
            samples: samples,
            initialSpeed: initialSpeed,
            initialTempo: initialTempo,
            globalVolume: max(0.1, min(1, globalVolume))
        )
    }

    private func parseSample(at offset: Int) throws -> TrackerSample {
        guard offset > 0, offset < data.count else { return .empty }
        var reader = BinaryReader(data: data, offset: offset)
        guard try reader.readString(length: 4) == "IMPS" else { return .empty }

        try reader.skip(12)
        try reader.skip(1)
        let globalVolume = Double(try reader.readUInt8()) / 64
        let flags = Int(try reader.readUInt8())
        let defaultVolume = Double(try reader.readUInt8()) / 64
        let name = try reader.readString(length: 26)
        let convert = Int(try reader.readUInt8())
        let defaultPan = Int(try reader.readUInt8())
        let length = Int(try reader.readUInt32LE())
        let loopStart = Int(try reader.readUInt32LE())
        let loopEnd = Int(try reader.readUInt32LE())
        let c5Speed = Double(try reader.readUInt32LE())
        try reader.skip(8)
        let samplePointer = Int(try reader.readUInt32LE())

        guard flags & 0x01 != 0,
              length > 0,
              samplePointer > 0,
              samplePointer < data.count else { return .empty }

        let is16Bit = flags & 0x02 != 0
        let isStereo = flags & 0x04 != 0
        let isCompressed = flags & 0x08 != 0
        guard !isCompressed else { return .empty }

        let signed = convert & 0x01 != 0
        let pcm = decodeITPCM(
            at: samplePointer,
            frameCount: length,
            is16Bit: is16Bit,
            isStereo: isStereo,
            signed: signed
        )

        let hasLoop = flags & 0x10 != 0
        let pingPong = flags & 0x40 != 0
        let pan = defaultPan & 0x80 != 0 ? Double(defaultPan & 0x7f) / 64 : 0.5

        return TrackerSample(
            name: name,
            pcm: pcm,
            volume: min(1, defaultVolume * max(0.0, min(1.0, globalVolume))),
            panning: min(1, max(0, pan)),
            c2Rate: c5Speed > 0 ? c5Speed : 8_363,
            loopStart: loopStart,
            loopLength: max(0, loopEnd - loopStart),
            loopMode: hasLoop ? (pingPong ? .pingPong : .forward) : .none
        )
    }

    private func parsePattern(at offset: Int) throws -> (pattern: TrackerPattern, usedChannels: Int) {
        guard offset > 0, offset < data.count else {
            return (TrackerPattern(rowCount: 64, channelCount: 64, events: Array(repeating: .empty, count: 64 * 64)), 1)
        }

        var reader = BinaryReader(data: data, offset: offset)
        let packedLength = Int(try reader.readUInt16LE())
        let rowCount = max(1, Int(try reader.readUInt16LE()))
        try reader.skip(4)
        let end = min(data.count, reader.offset + packedLength)

        var events = Array(repeating: TrackerEvent.empty, count: rowCount * 64)
        var masks = Array(repeating: 0, count: 64)
        var lastNote = Array(repeating: 0, count: 64)
        var lastInstrument = Array(repeating: 0, count: 64)
        var lastVolume = Array(repeating: 255, count: 64)
        var lastEffect = Array(repeating: 0, count: 64)
        var lastParameter = Array(repeating: 0, count: 64)
        var row = 0
        var usedChannels = 1

        while row < rowCount, reader.offset < end {
            let marker = Int(try reader.readUInt8())
            if marker == 0 {
                row += 1
                continue
            }

            let channel = (marker - 1) & 0x3f
            usedChannels = max(usedChannels, channel + 1)

            let mask: Int
            if marker & 0x80 != 0 {
                mask = Int(try reader.readUInt8())
                masks[channel] = mask
            } else {
                mask = masks[channel]
            }

            var note = 0
            var instrument = 0
            var volume = 255
            var effect = 0
            var parameter = 0

            if mask & 0x01 != 0 {
                note = Int(try reader.readUInt8())
                lastNote[channel] = note
            } else if mask & 0x10 != 0 {
                note = lastNote[channel]
            }

            if mask & 0x02 != 0 {
                instrument = Int(try reader.readUInt8())
                lastInstrument[channel] = instrument
            } else if mask & 0x20 != 0 {
                instrument = lastInstrument[channel]
            }

            if mask & 0x04 != 0 {
                volume = Int(try reader.readUInt8())
                lastVolume[channel] = volume
            } else if mask & 0x40 != 0 {
                volume = lastVolume[channel]
            }

            if mask & 0x08 != 0 {
                effect = Int(try reader.readUInt8())
                parameter = Int(try reader.readUInt8())
                lastEffect[channel] = effect
                lastParameter[channel] = parameter
            } else if mask & 0x80 != 0 {
                effect = lastEffect[channel]
                parameter = lastParameter[channel]
            }

            events[row * 64 + channel] = TrackerEvent(
                pitch: Self.pitch(fromITNote: note),
                instrument: instrument > 0 ? instrument : nil,
                volume: (0...64).contains(volume) ? volume : nil,
                command: Self.command(effect: effect, parameter: parameter)
            )
        }

        return (TrackerPattern(rowCount: rowCount, channelCount: 64, events: events), usedChannels)
    }

    private func trim(pattern: TrackerPattern, channelCount: Int) -> TrackerPattern {
        guard pattern.channelCount != channelCount else { return pattern }
        var events: [TrackerEvent] = []
        events.reserveCapacity(pattern.rowCount * channelCount)
        for row in 0..<pattern.rowCount {
            for channel in 0..<channelCount {
                events.append(pattern[row, channel])
            }
        }
        return TrackerPattern(rowCount: pattern.rowCount, channelCount: channelCount, events: events)
    }

    private func decodeITPCM(
        at offset: Int,
        frameCount: Int,
        is16Bit: Bool,
        isStereo: Bool,
        signed: Bool
    ) -> [Float] {
        let bytesPerSample = is16Bit ? 2 : 1
        let planes = isStereo ? 2 : 1
        let byteCount = frameCount * bytesPerSample * planes
        guard offset + byteCount <= data.count else { return [] }

        func monoValue(sampleIndex: Int, plane: Int) -> Float {
            let planeOffset = offset + plane * frameCount * bytesPerSample
            let byteOffset = planeOffset + sampleIndex * bytesPerSample

            if is16Bit {
                let word = UInt16(data[byteOffset]) | (UInt16(data[byteOffset + 1]) << 8)
                if signed {
                    return Float(Int16(bitPattern: word)) / 32_768
                } else {
                    return (Float(word) - 32_768) / 32_768
                }
            } else {
                let byte = data[byteOffset]
                if signed {
                    return Float(Int8(bitPattern: byte)) / 128
                } else {
                    return (Float(byte) - 128) / 128
                }
            }
        }

        var pcm: [Float] = []
        pcm.reserveCapacity(frameCount)
        for sampleIndex in 0..<frameCount {
            if isStereo {
                pcm.append((monoValue(sampleIndex: sampleIndex, plane: 0) + monoValue(sampleIndex: sampleIndex, plane: 1)) * 0.5)
            } else {
                pcm.append(monoValue(sampleIndex: sampleIndex, plane: 0))
            }
        }
        return pcm
    }

    private static func pitch(fromITNote note: Int) -> TrackerPitch? {
        switch note {
        case 1...120:
            return .midi(note + 11)
        case 253, 254:
            return .keyOff
        default:
            return nil
        }
    }

    private static func command(effect: Int, parameter: Int) -> TrackerCommand {
        guard effect != 0 || parameter != 0 else { return .none }

        switch effect {
        case 1:
            return parameter > 0 ? .setSpeed(parameter) : .none
        case 2:
            return .positionJump(parameter)
        case 3:
            return .patternBreak(parameter)
        case 4:
            return .volumeSlide(up: parameter >> 4, down: parameter & 0x0f)
        case 5:
            return .portamentoDown(parameter)
        case 6:
            return .portamentoUp(parameter)
        case 7:
            return .tonePortamento(parameter)
        case 8:
            return .vibrato(speed: parameter >> 4, depth: parameter & 0x0f)
        case 10:
            return .arpeggio(x: parameter >> 4, y: parameter & 0x0f)
        case 11:
            return .vibratoVolumeSlide(
                speed: 0,
                depth: 0,
                up: parameter >> 4,
                down: parameter & 0x0f
            )
        case 12:
            return .tonePortamentoVolumeSlide(
                portamento: 0,
                up: parameter >> 4,
                down: parameter & 0x0f
            )
        case 13:
            return .setVolume(min(64, parameter))
        case 15:
            return .sampleOffset(parameter * 256)
        case 16:
            return .panningSlide(left: parameter & 0x0f, right: parameter >> 4)
        case 17:
            return .retrigger(interval: parameter & 0x0f)
        case 18:
            return .tremolo(speed: parameter >> 4, depth: parameter & 0x0f)
        case 19:
            return specialCommand(parameter: parameter)
        case 20:
            return parameter > 0 ? .setTempo(parameter) : .none
        case 22:
            return .setGlobalVolume(parameter)
        case 23:
            return .globalVolumeSlide(up: parameter >> 4, down: parameter & 0x0f)
        case 24:
            return .panning(Double(parameter) / 255)
        default:
            return .raw(effect: effect, parameter: parameter)
        }
    }

    private static func specialCommand(parameter: Int) -> TrackerCommand {
        let subcommand = parameter >> 4
        let value = parameter & 0x0f

        switch subcommand {
        case 0x06:
            return .patternDelay(rows: value)
        case 0x0b:
            return .patternDelay(rows: value)
        case 0x0c:
            return .noteCut(tick: value)
        case 0x0d:
            return .noteDelay(tick: value)
        default:
            return .raw(effect: 19, parameter: parameter)
        }
    }
}
