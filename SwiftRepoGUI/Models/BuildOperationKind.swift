import Foundation

nonisolated enum BuildOperationKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case incrementalFrontend
    case incrementalSwiftRepo
    case incrementalEverything
    case buildScript
    case freshBuild
    case updateDependencies
    case updateAndRebuild
    case dependencyBuild

    var id: String { rawValue }

    var title: String {
        switch self {
        case .incrementalFrontend: "Incremental Frontend"
        case .incrementalSwiftRepo: "Incremental Swift Repo"
        case .incrementalEverything: "Incremental Everything"
        case .buildScript: "Full Build Script"
        case .freshBuild: "Fresh Rebuild"
        case .updateDependencies: "Update Dependencies"
        case .updateAndRebuild: "Update & Rebuild Changed"
        case .dependencyBuild: "Dependency Build"
        }
    }

    var symbolName: String {
        switch self {
        case .incrementalFrontend: "swift"
        case .incrementalSwiftRepo: "arrow.triangle.2.circlepath"
        case .incrementalEverything: "square.stack.3d.up"
        case .buildScript: "gearshape.2"
        case .freshBuild: "trash.circle"
        case .updateDependencies: "arrow.down.circle"
        case .updateAndRebuild: "arrow.triangle.merge"
        case .dependencyBuild: "folder"
        }
    }
}

enum BuildOperationStatus: String, Codable, CaseIterable {
    case pending
    case running
    case succeeded
    case failed
    case cancelled

    var title: String {
        switch self {
        case .pending: "Pending"
        case .running: "Running"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}