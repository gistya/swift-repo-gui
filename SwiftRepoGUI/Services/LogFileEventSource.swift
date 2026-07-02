import Foundation

/// Publishes a `Void` whenever the file at `url` changes — writes, growth, creation, deletion, or
/// rename/rotation — driven by DispatchSource file-system events instead of interval polling.
///
/// While the file does not exist its parent DIRECTORY is watched, so creation is caught promptly;
/// on delete/rename the watcher re-arms (log rotation reopens the fresh inode). An initial event is
/// emitted on (re)arm so subscribers do a first read without waiting for a change.
nonisolated final class LogFileEventSource: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "SwiftBuilder.LogFileEventSource")
    private let events = AsyncEventBroadcaster<Void>()
    private var source: (any DispatchSourceFileSystemObject)?
    private var watchingDirectory = false
    private var cancelled = false

    var stream: AsyncStream<Void> {
        events.stream(bufferingPolicy: .bufferingNewest(1))
    }

    init(url: URL) {
        self.url = url
    }

    func start() {
        queue.async { self.arm() }
    }

    func cancel() {
        queue.async {
            self.cancelled = true
            self.source?.cancel()
            self.source = nil
            self.events.finish()
        }
    }

    /// Open the file (or, if absent, its directory) and arm a DispatchSource on it. Runs on `queue`.
    private func arm() {
        guard !cancelled else { return }
        source?.cancel()
        source = nil

        let filePath = url.path
        var descriptor = open(filePath, O_EVTONLY)
        if descriptor >= 0 {
            watchingDirectory = false
        } else {
            descriptor = open(url.deletingLastPathComponent().path, O_EVTONLY)
            watchingDirectory = true
        }
        guard descriptor >= 0 else {
            // Even the parent directory is missing (e.g. the build folder not created yet): re-arm
            // slowly until it appears. This is the one deliberate timer, and it never runs once a
            // watchable path exists.
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.arm() }
            return
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: queue
        )
        newSource.setEventHandler { [weak self, weak newSource] in
            guard let self else { return }
            let events = newSource?.data ?? []
            self.events.yield { () }
            if self.watchingDirectory {
                // Directory activity: if our file has appeared, switch to watching it directly.
                if FileManager.default.fileExists(atPath: filePath) { self.arm() }
            } else if events.contains(.delete) || events.contains(.rename) {
                // The file went away (rotation): re-arm on whatever now exists.
                self.arm()
            }
        }
        newSource.setCancelHandler { close(descriptor) }
        source = newSource
        newSource.resume()

        // First read on (re)arm — the subscriber should not wait for the next change.
        events.yield { () }
    }
}
