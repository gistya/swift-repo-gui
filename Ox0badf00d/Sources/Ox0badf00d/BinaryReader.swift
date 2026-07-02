import Foundation

struct BinaryReader {
    let data: Data
    var offset: Int = 0

    var isAtEnd: Bool {
        offset >= data.count
    }

    init(data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    mutating func seek(_ newOffset: Int) throws {
        guard newOffset >= 0, newOffset <= data.count else {
            throw ModuleError.truncated("seek \(newOffset)")
        }
        offset = newOffset
    }

    mutating func skip(_ count: Int) throws {
        try seek(offset + count)
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset < data.count else {
            throw ModuleError.truncated("u8 at \(offset)")
        }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readInt8() throws -> Int8 {
        Int8(bitPattern: try readUInt8())
    }

    mutating func readUInt16LE() throws -> UInt16 {
        let low = UInt16(try readUInt8())
        let high = UInt16(try readUInt8())
        return low | (high << 8)
    }

    mutating func readUInt16BE() throws -> UInt16 {
        let high = UInt16(try readUInt8())
        let low = UInt16(try readUInt8())
        return (high << 8) | low
    }

    mutating func readInt16LE() throws -> Int16 {
        Int16(bitPattern: try readUInt16LE())
    }

    mutating func readUInt32LE() throws -> UInt32 {
        let b0 = UInt32(try readUInt8())
        let b1 = UInt32(try readUInt8()) << 8
        let b2 = UInt32(try readUInt8()) << 16
        let b3 = UInt32(try readUInt8()) << 24
        return b0 | b1 | b2 | b3
    }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= data.count else {
            throw ModuleError.truncated("bytes \(count) at \(offset)")
        }
        let bytes = Array(data[offset..<offset + count])
        offset += count
        return bytes
    }

    mutating func readData(_ count: Int) throws -> Data {
        Data(try readBytes(count))
    }

    mutating func readString(length: Int) throws -> String {
        let bytes = try readBytes(length)
        let trimmed = bytes.prefix { $0 != 0 }
        return String(bytes: trimmed, encoding: .isoLatin1)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

extension Data {
    subscript(safe index: Int) -> UInt8? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }

    func asciiString(at offset: Int, length: Int) -> String? {
        guard offset >= 0, offset + length <= count else { return nil }
        return String(bytes: self[offset..<offset + length], encoding: .ascii)
    }
}
