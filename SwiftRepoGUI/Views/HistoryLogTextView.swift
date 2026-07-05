import AppKit
import Matrix
import Observation
import SwiftUI

/// Loads completed build logs once, off the main actor, and keeps full text out of State snapshots.
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
                    LogTextView(text: loader.displayText, scroll: .top)
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
            MatrixLoader(.fun(.snake), size: 32.0, color: .terminalGreen, speed: 10.0, bloom: true, halo: 4.0)
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
