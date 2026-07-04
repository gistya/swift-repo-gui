import AppKit
import Observation
import SwiftUI

/// Loads completed build logs once, off the main actor, and keeps full text out of XState snapshots.
struct HistoryLogFileView: View {
    let operationID: UUID
    let logFileName: String?
    let fallback: String

    @State private var loader = HistoryLogLoader()

    init(operationID: UUID, logFileName: String? = nil, fallback: String) {
        self.operationID = operationID
        self.logFileName = logFileName
        self.fallback = fallback
    }

    var body: some View {
        GroupBox("Build Log") {
            ZStack {
                if loader.isLoading {
                    loadingView
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    HistoryScrollingTextView(text: loader.displayText)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
            }
            .animation(.easeInOut(duration: 0.24), value: loader.isLoading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .terminalText()
        .task(id: logIdentity) {
            do {
                try await loader.load(url: logURL(), fallback: fallback)
            } catch {
                loader.fail(localizedErrorMessage(for: error), fallback: fallback)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .frame(width: 32, height: 32)
            Text("Loading Log...")
                .font(.monaco(size: 13, weight: .bold))
                .foregroundStyle(Color.terminalGreen)
                .shadow(color: Color.terminalGreen.opacity(0.75), radius: 5)
            Text(logDisplayName)
                .font(.monaco(size: 10))
                .foregroundStyle(Color.terminalGreen.opacity(0.62))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 6))
    }

    private var logIdentity: String {
        "\(operationID.uuidString)-\(logFileName ?? "")"
    }

    private func logURL() throws -> URL {
        if let logFileName {
            return try AppPaths.logFileURL(named: logFileName)
        }
        return try AppPaths.logFileURL(for: operationID)
    }

    private var logDisplayName: String {
        if let logFileName, !logFileName.isEmpty {
            return URL(fileURLWithPath: logFileName).lastPathComponent
        }
        return "\(operationID.uuidString).log"
    }
}

@MainActor
@Observable
final class HistoryLogLoader {
    private(set) var text = ""
    private(set) var error: String?
    private(set) var isLoading = false

    @ObservationIgnored private var loadedURL: URL?

    var displayText: String {
        guard let error, !error.isEmpty else { return text }
        return "\(error)\n\n\(text)"
    }

    func load(url: URL, fallback: String) async throws {
        guard loadedURL != url || text.isEmpty else { return }
        loadedURL = url
        error = nil
        isLoading = true

        do {
            let loadedText = try await HistoryLogCache.shared.text(for: url, fallback: fallback)
            guard loadedURL == url else { return }
            withAnimation(.easeInOut(duration: 0.24)) {
                text = loadedText
                error = nil
                isLoading = false
            }
        } catch {
            guard loadedURL == url else { return }
            withAnimation(.easeInOut(duration: 0.24)) {
                self.error = localizedErrorMessage(for: error)
                text = fallback
                isLoading = false
            }
        }
    }

    func fail(_ message: String, fallback: String) {
        error = message
        text = fallback
        isLoading = false
    }
}

actor HistoryLogCache {
    static let shared = HistoryLogCache()

    private var cachedText: [String: String] = [:]
    private var inFlightLoads: [String: Task<String, any Error>] = [:]

    func text(for url: URL, fallback: String) async throws -> String {
        let key = url.standardizedFileURL.path
        if let cached = cachedText[key] {
            return cached
        }
        if let load = inFlightLoads[key] {
            return try await load.value
        }

        let load = Task.detached(priority: .utility) {
            try Self.readLog(at: url, fallback: fallback)
        }
        inFlightLoads[key] = load

        do {
            let value = try await load.value
            cachedText[key] = value
            inFlightLoads[key] = nil
            return value
        } catch {
            inFlightLoads[key] = nil
            throw error
        }
    }

    private nonisolated static func readLog(at url: URL, fallback: String) throws -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return fallback
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var chunks: [String] = []
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: 512 * 1024), !chunk.isEmpty else {
                break
            }
            chunks.append(String(decoding: chunk, as: UTF8.self))
        }

        return chunks.joined()
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

private struct HistoryScrollingTextView: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .lineBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(SwiftBuilderStyle.current.colors.terminalBlack)

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(SwiftBuilderStyle.current.colors.terminalBlack)
        textView.textColor = NSColor(SwiftBuilderStyle.current.colors.terminalGreen)
        textView.insertionPointColor = NSColor(SwiftBuilderStyle.current.colors.terminalGreen)
        textView.font = NSFont(name: SwiftBuilderStyle.current.fonts.monospaceName, size: 11)
            ?? .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard context.coordinator.currentText != text else { return }
        context.coordinator.currentText = text
        context.coordinator.textView?.string = text
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    final class Coordinator {
        weak var textView: NSTextView?
        var currentText = ""
    }
}

private extension NSColor {
    convenience init(_ styleColor: StyleColor) {
        self.init(
            calibratedRed: styleColor.red,
            green: styleColor.green,
            blue: styleColor.blue,
            alpha: styleColor.opacity
        )
    }
}
