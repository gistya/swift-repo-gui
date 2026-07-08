import Foundation
import Observation
import SwiftRepoCore
import SwiftUI

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
