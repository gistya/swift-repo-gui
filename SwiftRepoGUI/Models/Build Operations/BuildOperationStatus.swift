import Foundation

enum BuildOperationStatus: String, Codable, CaseIterable {
    case pending
    case running
    case succeeded
    case failed
    case cancelled

    var title: String {
        switch self {
        case .pending: String(localized: "Pending")
        case .running: String(localized: "Running")
        case .succeeded: String(localized: "Succeeded")
        case .failed: String(localized: "Failed")
        case .cancelled: String(localized: "Cancelled")
        }
    }
}
