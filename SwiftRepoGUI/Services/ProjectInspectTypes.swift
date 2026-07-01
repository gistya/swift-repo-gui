import Foundation

nonisolated enum ProjectInspectMode: Sendable, Equatable {
    case fullInspect
    case revisionsOnly
}

nonisolated struct RepositoryCandidate: Sendable, Equatable, Hashable {
    let name: String
    let path: URL

    var isPrimary: Bool { name == "swift" }
}

nonisolated struct ValidatedProjectSnapshot: Sendable, Equatable {
    let root: URL
    let swiftDirectory: URL
    let buildScript: URL
    let updateCheckout: URL
    let buildRoot: URL
    let candidates: [RepositoryCandidate]
    let detectedBuildSubdirs: [String]
    let swiftBuildDirectoryName: String
    let checkoutScheme: String
    let swiftBranch: String
    let schemeResolutionSource: SchemeResolutionSource
    let availableCheckoutSchemes: [String]
}

nonisolated struct ProjectInspectInput: Sendable, Equatable {
    let projectPath: String
    let checkoutSchemeOverride: String
    let selectedBuildSubdir: String
    let mode: ProjectInspectMode
    let existingCandidates: [RepositoryCandidate]
}

nonisolated struct ProjectInspectOutput: Sendable, Equatable {
    let mode: ProjectInspectMode
    let snapshot: ValidatedProjectSnapshot?
    let repositories: [SwiftRepository]
}

nonisolated enum ProjectInspectFailure: Error, LocalizedError, Sendable {
    case missingInput
    case projectNotLoaded

    var errorDescription: String? {
        switch self {
        case .missingInput:
            "Project inspection did not receive any input."
        case .projectNotLoaded:
            "Load a project before capturing revisions."
        }
    }
}
