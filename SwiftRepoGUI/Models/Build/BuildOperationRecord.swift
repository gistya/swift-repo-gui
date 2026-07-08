import Foundation
import SwiftData
import SwiftRepoCore

@Model
final class BuildOperationRecord {
    @Attribute(.unique) var id: UUID
    var data: BuildOperationRecordData
    
    var createdAt: Date {
        get { data.createdAt }
        set { data.createdAt = newValue }
    }
    
    var finishedAt: Date? {
        get { data.finishedAt }
        set { data.finishedAt = newValue }
    }
    
    var kindRaw: String {
        get { data.kindRaw }
        set { data.kindRaw = newValue }
    }
    
    var statusRaw: String {
        get { data.statusRaw }
        set { data.statusRaw = newValue }
    }
    
    var projectPath: String {
        get { data.projectPath }
        set { data.projectPath = newValue }
    }
    
    var buildSubdir: String {
        get { data.buildSubdir }
        set { data.buildSubdir = newValue }
    }
    
    var targetRepository: String {
        get { data.targetRepository }
        set { data.targetRepository = newValue }
    }
    
    var commandLine: String {
        get { data.commandLine }
        set { data.commandLine = newValue }
    }
    
    var logFileName: String {
        get { data.logFileName }
        set { data.logFileName = newValue }
    }
    
    var optionsJSON: Data {
        get { data.optionsJSON }
        set { data.optionsJSON = newValue }
    }
    
    var exitCode: Int? {
        get { data.exitCode }
        set { data.exitCode = newValue }
    }
    
    var progress: Double {
        get { data.progress }
        set { data.progress = newValue }
    }
    
    var etaSeconds: Double? {
        get { data.etaSeconds }
        set { data.etaSeconds = newValue }
    }
    
    var notes: String {
        get { data.notes }
        set { data.notes = newValue }
    }
    
    var savedProfileName: String? {
        get { data.savedProfileName }
        set { data.savedProfileName = newValue }
    }

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

        self.data = BuildOperationRecordData(
            createdAt: createdAt,
            finishedAt: nil,
            kindRaw: kind.rawValue,
            statusRaw: status.rawValue,
            projectPath: projectPath,
            buildSubdir: buildSubdir,
            targetRepository: targetRepository,
            commandLine: commandLine,
            logFileName: logFileName,
            optionsJSON: (try? BuildOptionsCoding.encode(options)) ?? Data(),
            progress: 0,
            notes: notes,
            savedProfileName: savedProfileName
        )
    }
}




