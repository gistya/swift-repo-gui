import CompositionalInit
import Foundation

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
