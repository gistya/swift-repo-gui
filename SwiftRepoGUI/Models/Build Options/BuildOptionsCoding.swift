import Foundation

nonisolated public enum BuildOptionsCodingError: Error, LocalizedError, Sendable {
    case encodeFailed(underlying: String)
    case decodeFailed(underlying: String)

    public var errorDescription: String? {
        switch self {
        case let .encodeFailed(underlying):
            "Could not save build options: \(underlying)"
        case let .decodeFailed(underlying):
            "Could not read saved build options: \(underlying)"
        }
    }
}

nonisolated public enum BuildOptionsCoding {
    public static func encode(_ options: BuildOptions) throws -> Data {
        do {
            return try JSONEncoder().encode(options)
        } catch {
            throw BuildOptionsCodingError.encodeFailed(underlying: error.localizedDescription)
        }
    }

    public static func decode(_ data: Data) throws -> BuildOptions {
        guard !data.isEmpty else { return .default }
        do {
            return try JSONDecoder().decode(BuildOptions.self, from: data)
        } catch {
            throw BuildOptionsCodingError.decodeFailed(underlying: error.localizedDescription)
        }
    }
}

nonisolated public struct LastUsedBuildSettings: Codable, Equatable, Sendable {
    public var options: BuildOptions
    public var selectedRepository: String
}

nonisolated public enum LastUsedBuildSettingsStore {
    private static let key = "lastUsedBuildSettings"

    public static func load(from defaults: UserDefaults = .standard) -> LastUsedBuildSettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LastUsedBuildSettings.self, from: data)
    }

    public static func save(
        options: BuildOptions,
        selectedRepository: String,
        to defaults: UserDefaults = .standard
    ) {
        let snapshot = LastUsedBuildSettings(
            options: options,
            selectedRepository: selectedRepository.isEmpty ? "swift" : selectedRepository
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
