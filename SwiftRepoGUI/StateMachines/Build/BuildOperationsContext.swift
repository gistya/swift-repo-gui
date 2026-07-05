import Foundation
import SwiftXState

nonisolated struct BuildOperationsContext: Sendable, Equatable {
    var activeJob: BuildJob?
    var progress: BuildProgressSnapshot = .zero
    var statusMessage: String?
    var lastExitCode: Int32?
    var lastOperationID: UUID?
    var startedAt: Date?

    var isRunning: Bool { activeJob != nil }
}
