import Foundation
import SwiftRepoCore

nonisolated struct ExportedBuildOperation: Codable, Sendable {
    var id: UUID
    var createdAt: Date
    var kind: BuildOperationKind
    var projectPath: String
    var buildSubdir: String
    var targetRepository: String
    var commandLine: String
    var options: BuildOptions
    var notes: String
    var savedProfileName: String?

    init(from record: BuildOperationRecord) {
        id = record.id
        createdAt = record.createdAt
        kind = record.kind
        projectPath = record.projectPath
        buildSubdir = record.buildSubdir
        targetRepository = record.targetRepository
        commandLine = record.commandLine
        options = record.options
        notes = record.notes
        savedProfileName = record.savedProfileName
    }
}
