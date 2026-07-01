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

    var succeeded: Bool { exitCode == 0 && errorMessage == nil }
}

nonisolated enum BuildProcessRunnerError: Error, LocalizedError, Sendable {
    case logFileCreationFailed(path: String, underlying: String)
    case logFileUnavailable(path: String, underlying: String)
    case logWriteFailed(path: String, underlying: String)
    case logCloseFailed(path: String, underlying: String)
    case invalidLogLineEncoding

    var errorDescription: String? {
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

/// Append-only writer for the per-build log file on disk.
private final class BuildLogWriter: @unchecked Sendable {
    private let path: String
    private let handle: FileHandle

    nonisolated init(path: String) throws {
        self.path = path
        do {
            handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        } catch {
            throw BuildProcessRunnerError.logFileUnavailable(path: path, underlying: error.localizedDescription)
        }
    }

    nonisolated func append(_ text: String) throws {
        guard !text.isEmpty else { return }
        let normalized = Self.normalizedLogText(text)
        guard let data = normalized.data(using: .utf8) else {
            throw BuildProcessRunnerError.invalidLogLineEncoding
        }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch let error as BuildProcessRunnerError {
            throw error
        } catch {
            throw BuildProcessRunnerError.logWriteFailed(path: path, underlying: error.localizedDescription)
        }
    }

    nonisolated func close() throws {
        do {
            try handle.close()
        } catch {
            throw BuildProcessRunnerError.logCloseFailed(path: path, underlying: error.localizedDescription)
        }
    }

    nonisolated func closeAfterFailure() {
        do {
            try handle.close()
        } catch {
            // Primary write/encoding error is already propagating.
        }
    }

    private nonisolated static func normalizedLogText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

private nonisolated struct BuildOutputTail: Sendable {
    private let maxCharacters: Int
    private var storage = ""

    init(maxCharacters: Int = 12_000) {
        self.maxCharacters = maxCharacters
    }

    mutating func append(_ text: String) {
        guard !text.isEmpty else { return }
        storage += text
        if storage.count > maxCharacters {
            storage = String(storage.suffix(maxCharacters))
        }
    }

    var text: String {
        storage.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Owns non-Sendable `Process` / `FileHandle` values for background pipe draining.
private final class ProcessPipeReader: @unchecked Sendable {
    let process: Process
    let readHandle: FileHandle

    nonisolated init(process: Process, readHandle: FileHandle) {
        self.process = process
        self.readHandle = readHandle
    }

    nonisolated func drain(
        logPath: String,
        startedAt: Date,
        onProgress: @escaping @Sendable (BuildProgressSnapshot) -> Void
    ) throws -> String {
        let logWriter = try BuildLogWriter(path: logPath)
        var outputTail = BuildOutputTail()
        do {
            var progress = BuildProgressSnapshot.zero
            var buffer = ""

            while !Task.isCancelled {
                let data = readHandle.availableData
                if data.isEmpty { break }
                let chunk = String(decoding: data, as: UTF8.self)
                let normalizedChunk = Self.normalizedLogText(chunk)
                try logWriter.append(normalizedChunk)
                outputTail.append(normalizedChunk)
                buffer += chunk

                while let record = Self.popRecord(from: &buffer) {
                    progress = ProgressParser.parse(line: record, startedAt: startedAt, previous: progress)
                    onProgress(progress)
                }

                if !buffer.isEmpty {
                    progress = ProgressParser.parse(line: buffer, startedAt: startedAt, previous: progress)
                    onProgress(progress)
                }
            }

            if !buffer.isEmpty {
                progress = ProgressParser.parse(line: buffer, startedAt: startedAt, previous: progress)
                onProgress(progress)
            }
        } catch {
            logWriter.closeAfterFailure()
            throw error
        }

        try logWriter.close()
        return outputTail.text
    }

    private nonisolated static func popRecord(from buffer: inout String) -> String? {
        guard let separatorIndex = buffer.firstIndex(where: { $0 == "\n" || $0 == "\r" }) else {
            return nil
        }

        let record = String(buffer[..<separatorIndex])
        var nextIndex = buffer.index(after: separatorIndex)
        if buffer[separatorIndex] == "\r",
           nextIndex < buffer.endIndex,
           buffer[nextIndex] == "\n" {
            nextIndex = buffer.index(after: nextIndex)
        }
        buffer = String(buffer[nextIndex...])
        return record
    }

    private nonisolated static func normalizedLogText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    nonisolated func waitForExit() {
        process.waitUntilExit()
    }

    nonisolated func terminateIfRunning() {
        if process.isRunning {
            process.terminate()
        }
    }
}

nonisolated enum BuildProcessRunner {
    static func run(
        job: BuildJob,
        swiftSourceRoot: String?,
        swiftBuildRoot: String?,
        onProgress: @escaping @Sendable (BuildProgressSnapshot) -> Void
    ) async throws -> BuildProcessResult {
        try prepareLogFile(at: job.logFilePath)
        try appendLaunchHeader(for: job)
        onProgress(BuildProgressSnapshot(
            completedSteps: 0,
            totalSteps: 0,
            fraction: 0,
            etaSeconds: nil,
            message: "Launching: \(job.displayCommand)"
        ))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: job.executable)
        process.arguments = job.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: job.workingDirectory, isDirectory: true)

        var environment = processEnvironment()
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

        do {
            try process.run()
        } catch {
            let message = "Failed to launch process: \(localizedErrorMessage(for: error))"
            try? appendDiagnostic(message, to: job.logFilePath)
            throw error
        }

        let (exitCode, logError, outputTail): (Int32, String?, String) = await withTaskCancellationHandler {
            await Task.detached(priority: .utility) {
                var capturedLogError: String?
                var capturedOutputTail = ""
                do {
                    capturedOutputTail = try reader.drain(
                        logPath: job.logFilePath,
                        startedAt: startedAt,
                        onProgress: onProgress
                    )
                } catch {
                    capturedLogError = localizedErrorMessage(for: error)
                }
                reader.waitForExit()
                return (reader.process.terminationStatus, capturedLogError, capturedOutputTail)
            }.value
        } onCancel: {
            reader.terminateIfRunning()
        }

        if exitCode != 0 {
            try? appendDiagnostic("Process exited with code \(exitCode).", to: job.logFilePath)
        }

        return BuildProcessResult(
            exitCode: exitCode,
            errorMessage: combinedErrorMessage(
                exitCode: exitCode,
                logError: logError,
                outputTail: outputTail
            )
        )
    }

    private static func prepareLogFile(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: url, options: .atomic)
        } catch {
            throw BuildProcessRunnerError.logFileCreationFailed(
                path: path,
                underlying: error.localizedDescription
            )
        }
    }

    private static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let fallbackPath = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]

        var seen: Set<String> = []
        let mergedPath = (existingPath + fallbackPath).filter { entry in
            !entry.isEmpty && seen.insert(entry).inserted
        }
        environment["PATH"] = mergedPath.joined(separator: ":")
        return environment
    }

    private static func appendDiagnostic(_ message: String, to path: String) throws {
        let writer = try BuildLogWriter(path: path)
        do {
            try writer.append("\n\(message)\n")
            try writer.close()
        } catch {
            writer.closeAfterFailure()
            throw error
        }
    }

    private static func appendLaunchHeader(for job: BuildJob) throws {
        let writer = try BuildLogWriter(path: job.logFilePath)
        do {
            try writer.append("""
            Working directory: \(job.workingDirectory)
            Command: \(job.displayCommand)

            """)
            try writer.close()
        } catch {
            writer.closeAfterFailure()
            throw error
        }
    }

    private static func combinedErrorMessage(
        exitCode: Int32,
        logError: String?,
        outputTail: String
    ) -> String? {
        var parts: [String] = []
        if let logError, !logError.isEmpty {
            parts.append(logError)
        }
        if exitCode != 0 {
            parts.append("Process exited with code \(exitCode).")
        }
        if !parts.isEmpty, let formattedOutput = formattedOutputTail(outputTail) {
            parts.append("Last output:\n\(formattedOutput)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    private static func formattedOutputTail(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(80).joined(separator: "\n")
    }
}
