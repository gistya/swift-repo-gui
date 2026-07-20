import Foundation

nonisolated public enum ToolchainLoadError: Error, LocalizedError, Sendable {
    case missingPresetFile
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingPresetFile: "No swift/utils/build-presets.ini — choose a swift project first."
        case let .parseFailed(message): "Could not read build-presets.ini: \(message)"
        }
    }
}
