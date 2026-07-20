import Foundation

nonisolated public enum BuildProcessRunnerError: Error, LocalizedError, Sendable {
    case logFileCreationFailed(path: String, underlying: String)
    case logFileUnavailable(path: String, underlying: String)
    case logWriteFailed(path: String, underlying: String)
    case logCloseFailed(path: String, underlying: String)
    case invalidLogLineEncoding

    public var errorDescription: String? {
        switch self {
        case let .logFileCreationFailed(path, underlying):
            "Could not create build log at \(path): \(underlying)"
        case let .logFileUnavailable(path, underlying):
            "Could not open build log at \(path): \(underlying)"
        case let .logWriteFailed(path, underlying):
            "Could not write to build log at \(path): \(underlying)"
        case let .logCloseFailed(path, underlying):
            "Could not close build log at \(path): \(underlying)"
        case .invalidLogLineEncoding:
            "Build output contained text that could not be encoded as UTF-8."
        }
    }
}
