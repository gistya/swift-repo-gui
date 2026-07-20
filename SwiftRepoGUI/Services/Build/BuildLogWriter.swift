import Foundation

/// Append-only writer for the per-build log file on disk.
public final class BuildLogWriter: @unchecked Sendable {
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

    nonisolated public func append(_ text: String) throws {
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

    nonisolated public func close() throws {
        do {
            try handle.close()
        } catch {
            throw BuildProcessRunnerError.logCloseFailed(path: path, underlying: error.localizedDescription)
        }
    }

    nonisolated public func closeAfterFailure() {
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
