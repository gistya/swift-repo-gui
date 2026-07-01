import Foundation

nonisolated enum BuildOptionsCodingError: Error, LocalizedError, Sendable {
    case encodeFailed(underlying: String)
    case decodeFailed(underlying: String)

    var errorDescription: String? {
        switch self {
        case let .encodeFailed(underlying):
            "Could not save build options: \(underlying)"
        case let .decodeFailed(underlying):
            "Could not read saved build options: \(underlying)"
        }
    }
}

nonisolated enum BuildOptionsCoding {
    static func encode(_ options: BuildOptions) throws -> Data {
        do {
            return try JSONEncoder().encode(options)
        } catch {
            throw BuildOptionsCodingError.encodeFailed(underlying: error.localizedDescription)
        }
    }

    static func decode(_ data: Data) throws -> BuildOptions {
        guard !data.isEmpty else { return .default }
        do {
            return try JSONDecoder().decode(BuildOptions.self, from: data)
        } catch {
            throw BuildOptionsCodingError.decodeFailed(underlying: error.localizedDescription)
        }
    }
}