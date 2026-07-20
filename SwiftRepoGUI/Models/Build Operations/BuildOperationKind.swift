import Foundation

nonisolated public enum BuildOperationKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case incrementalFrontend
    case incrementalSwiftRepo
    case incrementalEverything
    case buildScript
    case freshBuild
    case updateDependencies
    case updateAndRebuild
    case dependencyBuild
    case buildToolchain

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .incrementalFrontend: coreLocalized("Incremental Frontend")
        case .incrementalSwiftRepo: coreLocalized("Incremental Swift Repo")
        case .incrementalEverything: coreLocalized("Incremental Everything")
        case .buildScript: coreLocalized("Full Build Script")
        case .freshBuild: coreLocalized("Fresh Rebuild")
        case .updateDependencies: coreLocalized("Update Dependencies")
        case .updateAndRebuild: coreLocalized("Update & Rebuild Changed")
        case .dependencyBuild: coreLocalized("Dependency Build")
        case .buildToolchain: coreLocalized("Build Toolchain")
        }
    }

    public var symbolName: String {
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


