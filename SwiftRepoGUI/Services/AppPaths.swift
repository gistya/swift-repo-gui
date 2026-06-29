import Foundation

enum AppPaths {
    static let bundleID = "com.physicalsoftware.SwiftRepoGUI"

    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var logsDirectory: URL {
        let dir = applicationSupport.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var exportsDirectory: URL {
        let dir = applicationSupport.appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func logFileURL(for operationID: UUID) -> URL {
        logsDirectory.appendingPathComponent("\(operationID.uuidString).log")
    }
}