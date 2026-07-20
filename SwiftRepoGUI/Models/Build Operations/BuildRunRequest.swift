import CompositionalInit
import Foundation

/// A value-semantic build intent that can cross from the main-actor UI/session into a SwiftXState
/// machine actor. The machine lowers this request into an executable `BuildJob`.
nonisolated public struct BuildRunRequest: Sendable, Equatable, Hashable, Blankable {
    public let operationID: UUID
    public let kind: BuildOperationKind
    public let project: SwiftProjectInfo
    public let buildSubdir: String
    public let options: BuildOptions
    public let targetRepository: String
    public let mode: BuildPlanningMode
    public let logFilePath: String
    /// Whether an update-checkout run should pass `--match-timestamp` (pin sibling repos to the commit
    /// matching the swift branch's HEAD date). Off by default; only the `.updateDependencies` kind uses it.
    public let matchTimestamp: Bool

    public init(
        operationID: UUID = UUID(),
        kind: BuildOperationKind,
        project: SwiftProjectInfo,
        buildSubdir: String,
        options: BuildOptions,
        targetRepository: String,
        mode: BuildPlanningMode = .command(),
        logFilePath: String,
        matchTimestamp: Bool = false
    ) {
        self.operationID = operationID
        self.kind = kind
        self.project = project
        self.buildSubdir = buildSubdir
        self.options = options
        self.targetRepository = targetRepository
        self.mode = mode
        self.logFilePath = logFilePath
        self.matchTimestamp = matchTimestamp
    }
    
    public static let _blank = Self(
        kind: .buildScript,
        project: ._blank,
        buildSubdir: ._blank,
        options: .default,
        targetRepository: ._blank,
        logFilePath: ._blank
    )
}
