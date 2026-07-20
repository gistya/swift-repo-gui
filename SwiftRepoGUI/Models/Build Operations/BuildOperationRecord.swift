import Foundation
import SwiftData

/// SwiftData record for a build/test/deploy operation.
///
/// The cross-platform value type is `BuildOperationRecordData` (in SwiftRepoCore); this `@Model`
/// stores the **individual columns** and exposes `data` as a computed bridge to that struct — the
/// same pattern the sibling models already use (`SavedBuildProfile.options`, `ToolchainRecipe.draft`,
/// `CustomPreset.value`).
///
/// Why not persist `BuildOperationRecordData` as a single attribute:
///  1. **Backward compatibility.** The existing store has one column per field (`ZCREATEDAT`,
///     `ZKINDRAW`, …). Collapsing them into one `data` blob is not a lightweight migration, so the
///     container fails to open and the app `fatalError`s on launch. Keeping the columns means the
///     current store loads with no migration and no data loss.
///  2. **Observation granularity.** SwiftData tracks each stored attribute separately, so a view
///     reading only `commandLine`/`status` isn't invalidated when `progress` changes. A single blob
///     attribute would invalidate every observer on any field change.
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

    /// Bridge to the cross-platform value type. Reads assemble it from the columns; writes fan back
    /// out to the columns (so SwiftData still tracks each field individually).
    var data: BuildOperationRecordData {
        get {
            BuildOperationRecordData(
                createdAt: createdAt,
                finishedAt: finishedAt,
                kindRaw: kindRaw,
                statusRaw: statusRaw,
                projectPath: projectPath,
                buildSubdir: buildSubdir,
                targetRepository: targetRepository,
                commandLine: commandLine,
                logFileName: logFileName,
                optionsJSON: optionsJSON,
                exitCode: exitCode,
                progress: progress,
                etaSeconds: etaSeconds,
                notes: notes,
                savedProfileName: savedProfileName
            )
        }
        set {
            createdAt = newValue.createdAt
            finishedAt = newValue.finishedAt
            kindRaw = newValue.kindRaw
            statusRaw = newValue.statusRaw
            projectPath = newValue.projectPath
            buildSubdir = newValue.buildSubdir
            targetRepository = newValue.targetRepository
            commandLine = newValue.commandLine
            logFileName = newValue.logFileName
            optionsJSON = newValue.optionsJSON
            exitCode = newValue.exitCode
            progress = newValue.progress
            etaSeconds = newValue.etaSeconds
            notes = newValue.notes
            savedProfileName = newValue.savedProfileName
        }
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
        self.createdAt = createdAt
        self.finishedAt = nil
        self.kindRaw = kind.rawValue
        self.statusRaw = status.rawValue
        self.projectPath = projectPath
        self.buildSubdir = buildSubdir
        self.targetRepository = targetRepository
        self.commandLine = commandLine
        self.logFileName = logFileName
        self.optionsJSON = (try? BuildOptionsCoding.encode(options)) ?? Data()
        self.exitCode = nil
        self.progress = 0
        self.etaSeconds = nil
        self.notes = notes
        self.savedProfileName = savedProfileName
    }
}
