import Foundation
import SwiftXState

nonisolated struct BuildJob: Sendable, Equatable, Hashable {
    let operationID: UUID
    let kind: BuildOperationKind
    let executable: String
    let arguments: [String]
    let workingDirectory: String
    let displayCommand: String
    let logFilePath: String
    let projectPath: String
    let buildSubdir: String
    let targetRepository: String
}

nonisolated struct BuildProcessResult: Sendable, Equatable {
    let exitCode: Int32
    let errorMessage: String?
}

/// Owns non-Sendable `Process` / `FileHandle` values for background pipe draining.
private final class ProcessPipeReader: @unchecked Sendable {
    let process: Process
    let readHandle: FileHandle

    init(process: Process, readHandle: FileHandle) {
        self.process = process
        self.readHandle = readHandle
    }

    func drain(
        logPath: String,
        startedAt: Date,
        onProgress: @escaping @Sendable (BuildProgressSnapshot) -> Void
    ) {
        guard let logHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) else { return }
        defer { try? logHandle.close() }

        var progress = BuildProgressSnapshot.zero
        var buffer = ""

        while !Task.isCancelled {
            let data = readHandle.availableData
            if data.isEmpty { break }
            guard let chunk = String(data: data, encoding: .utf8) else { continue }
            buffer += chunk
            while let range = buffer.range(of: "\n") {
                let line = String(buffer[..<range.lowerBound])
                buffer = String(buffer[range.upperBound...])
                if let lineData = (line + "\n").data(using: .utf8) {
                    try? logHandle.seekToEnd()
                    try? logHandle.write(contentsOf: lineData)
                }
                progress = ProgressParser.parse(line: line, startedAt: startedAt, previous: progress)
                onProgress(progress)
            }
        }

        if !buffer.isEmpty, let lineData = (buffer + "\n").data(using: .utf8) {
            try? logHandle.seekToEnd()
            try? logHandle.write(contentsOf: lineData)
        }
    }

    func waitForExit() {
        process.waitUntilExit()
    }
}

nonisolated enum BuildProcessRunner {
    static func run(
        job: BuildJob,
        swiftSourceRoot: String?,
        swiftBuildRoot: String?,
        onProgress: @escaping @Sendable (BuildProgressSnapshot) -> Void
    ) async throws -> BuildProcessResult {
        FileManager.default.createFile(atPath: job.logFilePath, contents: nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: job.executable)
        process.arguments = job.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: job.workingDirectory, isDirectory: true)

        var environment = ProcessInfo.processInfo.environment
        if let swiftSourceRoot { environment["SWIFT_SOURCE_ROOT"] = swiftSourceRoot }
        if let swiftBuildRoot { environment["SWIFT_BUILD_ROOT"] = swiftBuildRoot }
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let startedAt = Date()
        let reader = ProcessPipeReader(
            process: process,
            readHandle: outputPipe.fileHandleForReading
        )

        try process.run()

        let exitCode = try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                reader.drain(logPath: job.logFilePath, startedAt: startedAt, onProgress: onProgress)
                reader.waitForExit()
                return reader.process.terminationStatus
            }.value
        } onCancel: {
            if process.isRunning { process.terminate() }
        }

        return BuildProcessResult(
            exitCode: exitCode,
            errorMessage: exitCode == 0 ? nil : "Process exited with code \(exitCode)"
        )
    }
}