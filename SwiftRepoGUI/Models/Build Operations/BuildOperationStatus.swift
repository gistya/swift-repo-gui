import Foundation

public enum BuildOperationStatus: String, Codable, CaseIterable {
    case pending
    case running
    case succeeded
    case failed
    case cancelled

    public var title: String {
        switch self {
        case .pending: coreLocalized("Pending")
        case .running: coreLocalized("Running")
        case .succeeded: coreLocalized("Succeeded")
        case .failed: coreLocalized("Failed")
        case .cancelled: coreLocalized("Cancelled")
        }
    }
}
