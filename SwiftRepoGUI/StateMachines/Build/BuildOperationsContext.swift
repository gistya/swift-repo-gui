import Foundation
import SwiftXState

nonisolated public struct BuildOperationsContext: Sendable, Equatable {
    public var activeJob: BuildJob?
    public var progress: BuildProgressSnapshot = .zero
    public var statusMessage: String?
    public var lastExitCode: Int32?
    public var lastOperationID: UUID?
    public var startedAt: Date?

    public var isRunning: Bool { activeJob != nil }
}
