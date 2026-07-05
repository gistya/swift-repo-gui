import Foundation

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
