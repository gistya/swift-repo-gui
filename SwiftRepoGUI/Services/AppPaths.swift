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

    /// The app's data root: `~/Library/Application Support/com.physicalsoftware.SwiftRepoGUI` — the
    /// store, logs, and exports all live under here. Resolved from the real home (see
    /// `realHomeDirectory`) so it points at the actual, Finder-visible location even under the sandbox
    /// (where `FileManager` would hand back a container path).
    static func applicationSupportDirectory() throws -> URL {
        let dir = realHomeDirectory()
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
        try ensureDirectory(at: dir)
        return dir
    }

    /// The user's real home directory. `getpwuid` returns it even under the App Sandbox, where
    /// `NSHomeDirectory()` / `FileManager` would hand back the container path — so this reaches the
    /// Finder-visible `~/Documents` the user actually means.
    static func realHomeDirectory() -> URL {
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
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
