import Foundation

public struct BuildOperationRecordData: Hashable, Equatable, Codable, Sendable {
    public var createdAt: Date
    public var finishedAt: Date?
    public var kindRaw: String
    public var statusRaw: String
    public var projectPath: String
    public var buildSubdir: String
    public var targetRepository: String
    public var commandLine: String
    public var logFileName: String
    public var optionsJSON: Data
    public var exitCode: Int?
    public var progress: Double
    public var etaSeconds: Double?
    public var notes: String
    public var savedProfileName: String?
    
    public init(
        createdAt: Date,
        finishedAt: Date? = nil,
        kindRaw: String,
        statusRaw: String,
        projectPath: String,
        buildSubdir: String,
        targetRepository: String,
        commandLine: String,
        logFileName: String,
        optionsJSON: Data,
        exitCode: Int? = nil,
        progress: Double,
        etaSeconds: Double? = nil,
        notes: String,
        savedProfileName: String? = nil)
    {
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.kindRaw = kindRaw
        self.statusRaw = statusRaw
        self.projectPath = projectPath
        self.buildSubdir = buildSubdir
        self.targetRepository = targetRepository
        self.commandLine = commandLine
        self.logFileName = logFileName
        self.optionsJSON = optionsJSON
        self.exitCode = exitCode
        self.progress = progress
        self.etaSeconds = etaSeconds
        self.notes = notes
        self.savedProfileName = savedProfileName
    }
}
