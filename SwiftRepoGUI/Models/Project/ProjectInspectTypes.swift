import Foundation

nonisolated public enum ProjectInspectMode: Sendable, Equatable {
    case fullInspect
    case revisionsOnly
}

nonisolated public struct RepositoryCandidate: Sendable, Equatable, Hashable {
    public let name: String
    public let path: URL

    public var isPrimary: Bool { name == "swift" }
}

nonisolated public struct ProjectInspectInput: Sendable, Equatable {
    public let projectPath: String
    public let checkoutSchemeOverride: String
    public let selectedBuildSubdir: String
    public let mode: ProjectInspectMode
    public let existingCandidates: [RepositoryCandidate]
}

nonisolated public struct ProjectInspectOutput: Sendable, Equatable {
    public let mode: ProjectInspectMode
    public let snapshot: ValidatedProjectSnapshot?
    public let repositories: [SwiftRepository]
}

nonisolated public enum ProjectInspectFailure: Error, LocalizedError, Sendable {
    case missingInput
    case projectNotLoaded

    public var errorDescription: String? {
        switch self {
        case .missingInput:
            "Project inspection did not receive any input."
        case .projectNotLoaded:
            "Load a project before capturing revisions."
        }
    }
}
