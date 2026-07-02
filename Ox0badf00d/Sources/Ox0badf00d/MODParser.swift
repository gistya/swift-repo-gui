import Foundation

struct MODParser {
    let data: Data

    static func canParse(data: Data) -> Bool {
        guard data.count >= 1_084,
              let magic = data.asciiString(at: 1_080, length: 4) else { return false }
        return channelCount(for: magic) != nil
    }

    func parse() throws -> TrackerModule {
        var reader = BinaryReader(data: data)
        let title = try reader.readString(length: 20)
        var sampleHeaders: [MODSampleHeader] = []

        for _ in 0..<31 {
            let name = try reader.readString(length: 22)
            let length = Int(try reader.readUInt16BE()) * 2
            let rawFinetune = Int(try reader.readUInt8() & 0x0f)
            let finetune = rawFinetune > 7 ? rawFinetune - 16 : rawFinetune
            let volume = min(64, Int(try reader.readUInt8()))
            let loopStart = Int(try reader.readUInt16BE()) * 2
            let loopLength = Int(try reader.readUInt16BE()) * 2
            sampleHeaders.append(MODSampleHeader(
                name: name,
                length: length,
                finetune: finetune,
                volume: volume,
                loopStart: loopStart,
                loopLength: loopLength
            ))
        }

        let songLength = min(128, Int(try reader.readUInt8()))
        try reader.skip(1)
        let rawOrders = try reader.readBytes(128).map(Int.init)
        let magic = try reader.readString(length: 4)
        guard let channelCount = Self.channelCount(for: magic) else {
            throw ModuleError.invalidFormat("unknown MOD signature \(magic)")
        }

        let orders = Array(rawOrders.prefix(songLength)).filter { $0 < 128 }
        let patternCount = max((orders.max() ?? 0) + 1, 1)
        var patterns: [TrackerPattern] = []

        for _ in 0..<patternCount {
            var events = Array(
                repeating: TrackerEvent.empty,
                count: 64 * channelCount
            )

            for row in 0..<64 {
                for channel in 0..<channelCount {
                    let b0 = Int(try reader.readUInt8())
                    let b1 = Int(try reader.readUInt8())
                    let b2 = Int(try reader.readUInt8())
                    let b3 = Int(try reader.readUInt8())

                    let instrument = (b0 & 0xf0) | (b2 >> 4)
                    let period = ((b0 & 0x0f) << 8) | b1
                    let effect = b2 & 0x0f

                    events[row * channelCount + channel] = TrackerEvent(
                        pitch: period > 0 ? .amigaPeriod(period) : nil,
                        instrument: instrument > 0 ? instrument : nil,
                        command: Self.command(effect: effect, parameter: b3)
                    )
                }
            }

            patterns.append(TrackerPattern(
                rowCount: 64,
                channelCount: channelCount,
                events: events
            ))
        }

        var samples: [TrackerSample] = []
        for (index, header) in sampleHeaders.enumerated() {
            let end = min(data.count, reader.offset + header.length)
            let bytes = reader.offset < end ? Array(data[reader.offset..<end]) : []
            try reader.seek(min(data.count, reader.offset + header.length))
            let pcm = bytes.map { Float(Int8(bitPattern: $0)) / 128 }
            let loopMode: SampleLoopMode = header.loopLength > 2 ? .forward : .none
            samples.append(TrackerSample(
                name: header.name.isEmpty ? "Sample \(index + 1)" : header.name,
                pcm: pcm,
                volume: Double(header.volume) / 64,
                panning: 0.5,
                c2Rate: 8_363,
                finetuneCents: Double(header.finetune) * 100 / 8,
                loopStart: header.loopStart,
                loopLength: header.loopLength,
                loopMode: loopMode
            ))
        }

        return TrackerModule(
            format: .mod,
            title: title,
            channelCount: channelCount,
            orders: orders.isEmpty ? [0] : orders,
            patterns: patterns,
            samples: samples,
            initialSpeed: 6,
            initialTempo: 125,
            globalVolume: 0.82
        )
    }

    private static func channelCount(for magic: String) -> Int? {
        switch magic {
        case "M.K.", "M!K!", "M&K!", "N.T.", "FLT4":
            return 4
        case "FLT8", "CD81":
            return 8
        default:
            if magic.hasSuffix("CHN"),
               let first = magic.first,
               let count = Int(String(first)),
               count > 0 {
                return count
            }

            if magic.hasSuffix("CH"),
               let count = Int(magic.prefix(2).trimmingCharacters(in: .whitespaces)),
               count > 0 {
                return count
            }

            return nil
        }
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
}

private struct MODSampleHeader {
    let name: String
    let length: Int
    let finetune: Int
    let volume: Int
    let loopStart: Int
    let loopLength: Int
}
