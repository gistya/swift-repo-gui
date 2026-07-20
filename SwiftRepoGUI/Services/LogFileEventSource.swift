import Foundation

/// Publishes a `Void` whenever the file at `url` changes — writes, growth, creation, deletion, or
/// rename/rotation. An initial event is emitted on (re)arm so subscribers do a first read without
/// waiting for a change.
///
/// On Apple platforms this is driven by DispatchSource file-system events (kqueue). Those aren't
/// available in swift-corelibs Dispatch on Linux (no `makeFileSystemObjectSource`, no `O_EVTONLY`),
/// so Linux falls back to modification-time polling — coarser, but it keeps live log tailing working.
nonisolated public final class LogFileEventSource: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "SwiftBuilder.LogFileEventSource")
    private let events = AsyncEventBroadcaster<Void>()
    private var cancelled = false
#if canImport(Darwin)
    private var source: (any DispatchSourceFileSystemObject)?
    private var watchingDirectory = false
#else
    private var lastModified: Date?
#endif

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
#if canImport(Darwin)
            self.source?.cancel()
            self.source = nil
#endif
            self.events.finish()
        }
    }

#if canImport(Darwin)
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
#else
    /// Linux fallback: poll the file's modification time and yield on change (plus an initial read).
    /// Re-arms every second on `queue` until cancelled. Handles rotation/creation implicitly — a
    /// missing file reads as no mtime, and the first mtime after it (re)appears counts as a change.
    private func arm() {
        guard !cancelled else { return }
        let mod = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if mod != lastModified {
            lastModified = mod
            events.yield { () }
        }
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.arm() }
    }
#endif
}
