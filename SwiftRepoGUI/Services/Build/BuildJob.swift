import CompositionalInit
import Foundation

nonisolated struct BuildJob: Sendable, Equatable, Hashable, Blankable {
    let operationID: UUID
    let kind: BuildOperationKind
    let executable: String
    let arguments: [String]
    let workingDirectory: String
    let displayCommand: String
    let logFilePath: String
    let projectPath: String
    let buildSubdir: String
    let targetRepository: String
    
    static let _blank = Self(
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
