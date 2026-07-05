import Foundation

nonisolated struct SwiftRepository: Identifiable, Hashable, Sendable, Equatable {
    let name: String
    let path: URL
    var currentRevision: String?
    var isPrimary: Bool { name == "swift" }

    var id: String { name }
}
