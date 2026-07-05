import CompositionalInit
import Foundation

nonisolated enum BuildPlanningMode: Sendable, Equatable, Hashable {
    case command(changedRepositories: [SwiftRepository] = [])
    case freshNinjaClean
}

/// A value-semantic build intent that can cross from the main-actor UI/session into a SwiftXState
/// machine actor. The machine lowers this request into an executable `BuildJob`.
nonisolated struct BuildRunRequest: Sendable, Equatable, Hashable, Blankable {
    let operationID: UUID
    let kind: BuildOperationKind
    let project: SwiftProjectInfo
    let buildSubdir: String
    let options: BuildOptions
    let targetRepository: String
    let mode: BuildPlanningMode
    let logFilePath: String

    init(
        operationID: UUID = UUID(),
        kind: BuildOperationKind,
        project: SwiftProjectInfo,
        buildSubdir: String,
        options: BuildOptions,
        targetRepository: String,
        mode: BuildPlanningMode = .command(),
        logFilePath: String
    ) {
        self.operationID = operationID
        self.kind = kind
        self.project = project
        self.buildSubdir = buildSubdir
        self.options = options
        self.targetRepository = targetRepository
        self.mode = mode
        self.logFilePath = logFilePath
    }
    
    static let _blank = Self(
        kind: .buildScript,
        project: ._blank,
        buildSubdir: ._blank,
        options: .default,
        targetRepository: ._blank,
        logFilePath: ._blank
    )
}

/// Keeps command construction out of SwiftUI/session code. This is deliberately pure: given a
/// request snapshot, produce the exact process job the build machine should invoke.
nonisolated enum BuildJobPlanner {
    static func job(for request: BuildRunRequest) -> BuildJob {
        let planned = plannedCommand(for: request)
        return BuildJob(
            operationID: request.operationID,
            kind: request.kind,
            executable: planned.executable,
            arguments: planned.arguments,
            workingDirectory: planned.workingDirectory.path,
            displayCommand: planned.display,
            logFilePath: request.logFilePath,
            projectPath: request.project.root.path,
            buildSubdir: request.buildSubdir,
            targetRepository: displayedTargetRepository(for: request)
        )
    }

    private static func plannedCommand(
        for request: BuildRunRequest
    ) -> (executable: String, arguments: [String], display: String, workingDirectory: URL) {
        switch request.mode {
        case let .command(changedRepositories):
            return BuildCommandBuilder.command(
                kind: request.kind,
                project: request.project,
                buildSubdir: request.buildSubdir,
                options: request.options,
                targetRepository: request.targetRepository,
                changedRepositories: changedRepositories
            )
        case .freshNinjaClean:
            return BuildCommandBuilder.freshNinjaClean(
                project: request.project,
                buildSubdir: request.buildSubdir,
                repoName: request.targetRepository.isEmpty ? "swift" : request.targetRepository
            )
        }
    }

    private static func displayedTargetRepository(for request: BuildRunRequest) -> String {
        switch request.mode {
        case let .command(changedRepositories) where !changedRepositories.isEmpty:
            return changedRepositories.map(\.name).joined(separator: ", ")
        default:
            return request.targetRepository
        }
    }
}
