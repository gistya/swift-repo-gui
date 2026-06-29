import Foundation
import Observation

/// Polls a log file on a background interval so build output does not live in machine context.
@MainActor
@Observable
final class LogTailReader {
    private(set) var text = ""
    private var pollTask: Task<Void, Never>?
    private var trackedURL: URL?

    func track(url: URL) {
        guard trackedURL != url else { return }
        stop()
        trackedURL = url
        reload()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                await self?.reload()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        trackedURL = nil
    }

    func reload() {
        guard let trackedURL else { return }
        if let data = try? Data(contentsOf: trackedURL),
           let content = String(data: data, encoding: .utf8) {
            if content != text { text = content }
        }
    }
}