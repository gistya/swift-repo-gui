import Foundation

nonisolated public struct BuildOutputTail: Sendable {
    private let maxCharacters: Int
    private var storage = ""

    public init(maxCharacters: Int = 12_000) {
        self.maxCharacters = maxCharacters
    }

    public mutating func append(_ text: String) {
        guard !text.isEmpty else { return }
        storage += text
        if storage.count > maxCharacters {
            storage = String(storage.suffix(maxCharacters))
        }
    }

    public var text: String {
        storage.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
