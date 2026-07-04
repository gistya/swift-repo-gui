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
    case buildToolchain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .incrementalFrontend: String(localized: "Incremental Frontend")
        case .incrementalSwiftRepo: String(localized: "Incremental Swift Repo")
        case .incrementalEverything: String(localized: "Incremental Everything")
        case .buildScript: String(localized: "Full Build Script")
        case .freshBuild: String(localized: "Fresh Rebuild")
        case .updateDependencies: String(localized: "Update Dependencies")
        case .updateAndRebuild: String(localized: "Update & Rebuild Changed")
        case .dependencyBuild: String(localized: "Dependency Build")
        case .buildToolchain: String(localized: "Build Toolchain")
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
        case .buildToolchain: "shippingbox"
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
        case .pending: String(localized: "Pending")
        case .running: String(localized: "Running")
        case .succeeded: String(localized: "Succeeded")
        case .failed: String(localized: "Failed")
        case .cancelled: String(localized: "Cancelled")
        }
    }
}
