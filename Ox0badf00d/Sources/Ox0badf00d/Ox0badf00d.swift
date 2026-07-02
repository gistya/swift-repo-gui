import Foundation

public enum Ox0badf00d {
    public static let version = "0.1.0"
}

public enum TrackerFormat: String, Sendable {
    case mod = "MOD"
    case xm = "XM"
    case it = "IT"
}

public enum ModuleLoader {
    public static func load(data: Data) throws -> TrackerModule {
        if data.starts(with: Array("Extended Module: ".utf8)) {
            return try XMParser(data: data).parse()
        }

        if data.starts(with: Array("IMPM".utf8)) {
            return try ITParser(data: data).parse()
        }

        if MODParser.canParse(data: data) {
            return try MODParser(data: data).parse()
        }

        throw ModuleError.unsupportedFormat
    }

    public static func load(url: URL) throws -> TrackerModule {
        try load(data: Data(contentsOf: url))
    }
}

public enum ModuleError: Error, Equatable, LocalizedError {
    case unsupportedFormat
    case invalidFormat(String)
    case truncated(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "Unsupported tracker module format."
        case let .invalidFormat(message):
            "Invalid tracker module: \(message)"
        case let .truncated(message):
            "Truncated tracker module: \(message)"
        }
    }
}

extension Data {
    fileprivate func starts(with bytes: [UInt8]) -> Bool {
        guard count >= bytes.count else { return false }
        return zip(prefix(bytes.count), bytes).allSatisfy(==)
    }
}
