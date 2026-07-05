import Foundation

nonisolated struct BuildOutputTail: Sendable {
    private let maxCharacters: Int
    private var storage = ""

    init(maxCharacters: Int = 12_000) {
        self.maxCharacters = maxCharacters
    }

    mutating func append(_ text: String) {
        guard !text.isEmpty else { return }
        storage += text
        if storage.count > maxCharacters {
            storage = String(storage.suffix(maxCharacters))
        }
    }

    var text: String {
        storage.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
