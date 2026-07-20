import Foundation

/// Owns non-Sendable `Process` / `FileHandle` values for background pipe draining.
public final class ProcessPipeReader: @unchecked Sendable {
    public let process: Process
    public let readHandle: FileHandle

    nonisolated public init(process: Process, readHandle: FileHandle) {
        self.process = process
        self.readHandle = readHandle
    }

    nonisolated public func drain(
        logPath: String,
        startedAt: Date,
        baseStage: BuildStage,
        onProgress: @escaping @Sendable (BuildProgressSnapshot) -> Void
    ) throws -> String {
        let logWriter = try BuildLogWriter(path: logPath)
        var outputTail = BuildOutputTail()
        do {
            var progress = BuildProgressSnapshot.zero
            // Jobs that never emit build-script phase banners (raw ninja, update-checkout) stay in
            // their base stage the whole run; build-script/toolchain jobs advance from it via banners.
            progress.stage = baseStage
            var buffer = ""

            // Coalesce progress to ~10 Hz. A compiler build emits thousands of `[x/y]` lines per
            // second; forwarding every one drove O(build-lines) machine transitions + SwiftData
            // writes. Every complete record is still parsed (the log and the step counter stay
            // exact), but the latest snapshot is pushed onward at most once per 100 ms, with a final
            // flush so the terminal state is never lost.
            let minInterval: Duration = .milliseconds(100)
            var lastEmittedAt: ContinuousClock.Instant?
            var hasPendingEmit = false

            func flushProgress(force: Bool) {
                if !force, let last = lastEmittedAt, ContinuousClock.now - last < minInterval {
                    hasPendingEmit = true
                    return
                }
                onProgress(progress)
                lastEmittedAt = ContinuousClock.now
                hasPendingEmit = false
            }

            while !Task.isCancelled {
                let data = readHandle.availableData
                if data.isEmpty { break }
                let chunk = String(decoding: data, as: UTF8.self)
                let normalizedChunk = Self.normalizedLogText(chunk)
                try logWriter.append(normalizedChunk)
                outputTail.append(normalizedChunk)
                buffer += chunk

                // Parse only COMPLETE records; a trailing partial line stays in `buffer` for the next
                // chunk (parsing it produced half-formed messages that flashed in the UI).
                while let record = Self.popRecord(from: &buffer) {
                    progress = ProgressParser.parse(line: record, startedAt: startedAt, previous: progress)
                }
                flushProgress(force: false)
            }

            if hasPendingEmit {
                flushProgress(force: true)
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
           buffer[nextIndex] == "\n"
        {
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

    nonisolated public func waitForExit() {
        process.waitUntilExit()
    }

    nonisolated public func terminateIfRunning() {
        if process.isRunning {
            process.terminate()
        }
    }
}
