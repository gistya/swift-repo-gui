import Foundation
import Observation

/// Follows a log file reactively: DispatchSource file-system events (bridged through AsyncStream and
/// throttled) trigger incremental reads, so build output does not live in machine context and no
/// interval polling runs.
@MainActor
@Observable
final public class LogTailReader {
    nonisolated public static let maxBufferedBytes: UInt64 = 256 * 1024

    private(set) public var text = ""
    private(set) public var readError: String?
    private(set) public var isWaitingForFile = false
    private(set) public var fileSize: UInt64 = 0
    private(set) public var visibleStartOffset: UInt64 = 0
    @ObservationIgnored private var eventSource: LogFileEventSource?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    /// A change event arrived while a read was in flight — run one more read when it lands.
    private var pendingReload = false
    private var trackedURL: URL?
    private var readOffset: UInt64 = 0
    
    public init() {}

    public func track(url: URL) {
        guard trackedURL != url else { return }
        stop()
        trackedURL = url
        text = ""
        readOffset = 0
        reload()
        // File-system events (throttled — write storms collapse to one read per window) drive the
        // incremental reads; the source emits once on arm so the first read happens immediately.
        let source = LogFileEventSource(url: url)
        eventSource = source
        let events = source.stream
        eventTask = Task { [weak self] in
            for await _ in events {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.reload()
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        source.start()
    }

    public func stop() {
        eventTask?.cancel()
        eventTask = nil
        eventSource?.cancel()
        eventSource = nil
        loadTask?.cancel()
        loadTask = nil
        pendingReload = false
        trackedURL = nil
        readError = nil
        isWaitingForFile = false
        readOffset = 0
        fileSize = 0
        visibleStartOffset = 0
    }

    public func reload() {
        guard let trackedURL else { return }
        guard loadTask == nil else {
            pendingReload = true   // coalesce: re-read once the in-flight read finishes
            return
        }
        let offset = readOffset
        loadTask = Task(name: "com.swiftRepoCore.logTailLoader", priority: .medium) { [trackedURL] in
            defer {
                // Drain a change event that arrived while this read was in flight.
                if pendingReload {
                    pendingReload = false
                    reload()
                }
            }
            let result = await Self.readLog(at: trackedURL, offset: offset)
            guard !Task.isCancelled, self.trackedURL == trackedURL else { return }
            loadTask = nil
            switch result {
            case let .loaded(content, newOffset, fileSize, visibleStartOffset, reset):
                isWaitingForFile = false
                readError = nil
                self.fileSize = fileSize
                readOffset = newOffset
                if reset {
                    self.visibleStartOffset = visibleStartOffset
                    text = content
                } else if !content.isEmpty {
                    text += content
                }
                trimBufferedTextIfNeeded()
            case .missing:
                isWaitingForFile = true
                readError = nil
                fileSize = 0
                visibleStartOffset = 0
            case let .failed(message):
                isWaitingForFile = false
                readError = message
            }
        }
    }

    public var isShowingTail: Bool {
        visibleStartOffset > 0 || UInt64(text.utf8.count) >= Self.maxBufferedBytes
    }

    public var visibleByteDescription: String {
        let displayed = UInt64(text.utf8.count)
        guard fileSize > 0 else { return "" }
        if isShowingTail {
            return "Showing newest \(Self.formatBytes(displayed)) of \(Self.formatBytes(fileSize))."
        }
        return "Showing \(Self.formatBytes(displayed))."
    }

    nonisolated private static func readLog(at url: URL, offset: UInt64) async -> LogReadResult {
        await Task.detached(priority: .utility) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                return .missing
            }

            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
                let resetForTruncatedFile = fileSize < offset
                let requestedOffset = resetForTruncatedFile ? 0 : min(offset, fileSize)
                let earliestBufferedOffset = fileSize > Self.maxBufferedBytes ? fileSize - Self.maxBufferedBytes : 0
                let startOffset = max(requestedOffset, earliestBufferedOffset)
                let reset = resetForTruncatedFile || startOffset > offset

                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                try handle.seek(toOffset: startOffset)
                let data = try handle.readToEnd() ?? Data()

                let content = String(decoding: data, as: UTF8.self)
                return .loaded(
                    normalizedLogText(content),
                    startOffset + UInt64(data.count),
                    fileSize,
                    startOffset,
                    reset
                )
            } catch {
                return .failed(localizedErrorMessage(for: error))
            }
        }.value
    }

    nonisolated private static func normalizedLogText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func trimBufferedTextIfNeeded() {
        let currentByteCount = text.utf8.count
        let maxBytes = Int(Self.maxBufferedBytes)
        guard currentByteCount > maxBytes else { return }

        var utf8Start = text.utf8.index(text.utf8.endIndex, offsetBy: -maxBytes)
        while utf8Start < text.utf8.endIndex, String.Index(utf8Start, within: text) == nil {
            utf8Start = text.utf8.index(after: utf8Start)
        }
        guard let start = String.Index(utf8Start, within: text) else { return }

        let trimmed = String(text[start...])
        let removedBytes = UInt64(max(0, currentByteCount - trimmed.utf8.count))
        text = trimmed
        visibleStartOffset = min(fileSize, visibleStartOffset + removedBytes)
    }

    nonisolated private static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private enum LogReadResult: Sendable {
    case loaded(String, UInt64, UInt64, UInt64, Bool)
    case missing
    case failed(String)
}
