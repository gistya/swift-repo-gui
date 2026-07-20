import Foundation

nonisolated public struct SwiftRepository: Identifiable, Hashable, Sendable, Equatable {
    public let name: String
    public let path: URL
    public var currentRevision: String?
    public var isPrimary: Bool { name == "swift" }

    public var id: String { name }
}
