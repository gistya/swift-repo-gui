import Foundation
import SwiftXState

nonisolated public enum BuildProcessRunner {
    public static func run(
        job: BuildJob,
        swiftSourceRoot: String?,
        swiftBuildRoot: String?,
        onProgress: @escaping @Sendable (BuildProgressSnapshot) -> Void
    ) async throws -> BuildProcessResult {
        try prepareLogFile(at: job.logFilePath)
        try appendLaunchHeader(for: job)
        let baseStage = BuildStage.baseStage(for: job.kind)
        onProgress(BuildProgressSnapshot(
            completedSteps: 0,
            totalSteps: 0,
            fraction: 0,
            etaSeconds: nil,
            message: "Launching: \(job.displayCommand)",
            stage: baseStage
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
                        baseStage: baseStage,
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

        try? appendDiagnostic("Process exited with code \(exitCode).", to: job.logFilePath)

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
        // The build tools are Python (update-checkout, build-script). Python block-buffers stdout when
        // it's a pipe rather than a TTY, so its output — including errors like update-checkout's retry
        // loop — can sit unflushed for minutes and the log looks frozen after just the launch header.
        // Force line-by-line streaming so progress and failures reach the log as they happen.
        environment["PYTHONUNBUFFERED"] = "1"
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
