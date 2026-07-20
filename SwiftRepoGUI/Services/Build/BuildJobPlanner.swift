import CompositionalInit
import Foundation

nonisolated public enum BuildPlanningMode: Sendable, Equatable, Hashable {
    case command(changedRepositories: [SwiftRepository] = [])
    case freshNinjaClean
}

/// Keeps command construction out of SwiftUI/session code. This is deliberately pure: given a
/// request snapshot, produce the exact process job the build machine should invoke.
nonisolated public enum BuildJobPlanner {
    public static func job(for request: BuildRunRequest) -> BuildJob {
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
                changedRepositories: changedRepositories,
                matchTimestamp: request.matchTimestamp
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
