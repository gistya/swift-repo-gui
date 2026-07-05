import Foundation
import SwiftData

@Model
final class BuildOperationRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var finishedAt: Date?
    var kindRaw: String
    var statusRaw: String
    var projectPath: String
    var buildSubdir: String
    var targetRepository: String
    var commandLine: String
    var logFileName: String
    var optionsJSON: Data
    var exitCode: Int?
    var progress: Double
    var etaSeconds: Double?
    var notes: String
    var savedProfileName: String?

    var kind: BuildOperationKind {
        get { BuildOperationKind(rawValue: kindRaw) ?? .buildScript }
        set { kindRaw = newValue.rawValue }
    }

    var status: BuildOperationStatus {
        get { BuildOperationStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var options: BuildOptions {
        get {
            (try? BuildOptionsCoding.decode(optionsJSON)) ?? .default
        }
        set {
            optionsJSON = (try? BuildOptionsCoding.encode(newValue)) ?? Data()
        }
    }

    func decodedOptions() throws -> BuildOptions {
        try BuildOptionsCoding.decode(optionsJSON)
    }

    func updateOptions(_ options: BuildOptions) throws {
        optionsJSON = try BuildOptionsCoding.encode(options)
    }

    var duration: TimeInterval? {
        guard let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(createdAt)
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        kind: BuildOperationKind,
        status: BuildOperationStatus = .pending,
        projectPath: String,
        buildSubdir: String,
        targetRepository: String = "",
        commandLine: String,
        logFileName: String,
        options: BuildOptions = .default,
        notes: String = "",
        savedProfileName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kindRaw = kind.rawValue
        self.statusRaw = status.rawValue
        self.projectPath = projectPath
        self.buildSubdir = buildSubdir
        self.targetRepository = targetRepository
        self.commandLine = commandLine
        self.logFileName = logFileName
        self.optionsJSON = (try? BuildOptionsCoding.encode(options)) ?? Data()
        self.progress = 0
        self.notes = notes
        self.savedProfileName = savedProfileName
    }
}

@Model
final class SavedBuildProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var optionsJSON: Data
    var defaultKindRaw: String
    var notes: String

    var defaultKind: BuildOperationKind {
        get { BuildOperationKind(rawValue: defaultKindRaw) ?? .buildScript }
        set { defaultKindRaw = newValue.rawValue }
    }

    var options: BuildOptions {
        get {
            (try? BuildOptionsCoding.decode(optionsJSON)) ?? .default
        }
        set {
            optionsJSON = (try? BuildOptionsCoding.encode(newValue)) ?? Data()
            updatedAt = .now
        }
    }

    func updateOptions(_ options: BuildOptions) throws {
        optionsJSON = try BuildOptionsCoding.encode(options)
        updatedAt = .now
    }

    init(
        id: UUID = UUID(),
        name: String,
        options: BuildOptions = .default,
        defaultKind: BuildOperationKind = .buildScript,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
        self.optionsJSON = (try? BuildOptionsCoding.encode(options)) ?? Data()
        self.defaultKindRaw = defaultKind.rawValue
        self.notes = notes
    }
}

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