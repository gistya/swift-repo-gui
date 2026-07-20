import CompositionalInit
import Foundation

nonisolated public struct BuildJob: Sendable, Equatable, Hashable, Blankable {
    public let operationID: UUID
    public let kind: BuildOperationKind
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String
    public let displayCommand: String
    public let logFilePath: String
    public let projectPath: String
    public let buildSubdir: String
    public let targetRepository: String
    
    public init(operationID: UUID, kind: BuildOperationKind, executable: String, arguments: [String], workingDirectory: String, displayCommand: String, logFilePath: String, projectPath: String, buildSubdir: String, targetRepository: String) {
        self.operationID = operationID
        self.kind = kind
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.displayCommand = displayCommand
        self.logFilePath = logFilePath
        self.projectPath = projectPath
        self.buildSubdir = buildSubdir
        self.targetRepository = targetRepository
    }
    
    public static let _blank = Self(
        operationID: ._blank,
        kind: .buildScript,
        executable: ._blank,
        arguments: [],
        workingDirectory: ._blank,
        displayCommand: ._blank,
        logFilePath: ._blank,
        projectPath: ._blank,
        buildSubdir: ._blank,
        targetRepository: ._blank
    )
}
