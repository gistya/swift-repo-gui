import Foundation
import SwiftData
import SwiftRepoCore

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
