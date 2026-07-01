import Foundation

nonisolated enum AppPathsError: Error, LocalizedError, Sendable {
    case missingApplicationSupportDirectory
    case cannotCreateDirectory(path: String, underlying: String)
    case missingLogFileName

    var errorDescription: String? {
        switch self {
        case .missingApplicationSupportDirectory:
            "Could not locate the Application Support directory."
        case let .cannotCreateDirectory(path, underlying):
            "Could not create directory at \(path): \(underlying)"
        case .missingLogFileName:
            "No log file was captured for this operation."
        }
    }
}

nonisolated enum AppPaths {
    static let bundleID = "com.physicalsoftware.SwiftRepoGUI"

    static func applicationSupportDirectory() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppPathsError.missingApplicationSupportDirectory
        }
        let dir = base.appendingPathComponent(bundleID, isDirectory: true)
        try ensureDirectory(at: dir)
        return dir
    }

    static func logsDirectory() throws -> URL {
        let dir = try applicationSupportDirectory().appendingPathComponent("logs", isDirectory: true)
        try ensureDirectory(at: dir)
        return dir
    }

    static func exportsDirectory() throws -> URL {
        let dir = try applicationSupportDirectory().appendingPathComponent("exports", isDirectory: true)
        try ensureDirectory(at: dir)
        return dir
    }

    static func logFileURL(for operationID: UUID) throws -> URL {
        try logsDirectory().appendingPathComponent("\(operationID.uuidString).log")
    }

    static func logFileURL(named fileName: String) throws -> URL {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppPathsError.missingLogFileName }

        if trimmed.contains("/") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        let safeName = URL(fileURLWithPath: trimmed).lastPathComponent
        guard !safeName.isEmpty else { throw AppPathsError.missingLogFileName }
        return try logsDirectory().appendingPathComponent(safeName)
    }

    private static func ensureDirectory(at url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw AppPathsError.cannotCreateDirectory(path: url.path, underlying: error.localizedDescription)
        }
    }
}
