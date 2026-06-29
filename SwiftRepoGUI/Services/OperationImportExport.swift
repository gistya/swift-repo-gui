import Foundation
import UniformTypeIdentifiers

enum OperationImportExport {
    static let operationUTType = UTType(filenameExtension: "swiftbuildop") ?? .json

    static func export(_ operation: ExportedBuildOperation) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(operation)
    }

    static func importOperation(from data: Data) throws -> ExportedBuildOperation {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExportedBuildOperation.self, from: data)
    }

    static func writeExportFile(_ operation: ExportedBuildOperation) throws -> URL {
        let data = try export(operation)
        let fileName = "operation-\(operation.id.uuidString.prefix(8))-\(operation.kind.rawValue).swiftbuildop"
        let url = AppPaths.exportsDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }
}