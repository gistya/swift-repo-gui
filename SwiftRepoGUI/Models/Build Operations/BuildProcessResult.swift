nonisolated public struct BuildProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let errorMessage: String?
    public var succeeded: Bool { exitCode == 0 && errorMessage == nil }
}
