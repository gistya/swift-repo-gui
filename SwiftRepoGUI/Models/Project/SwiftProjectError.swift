import Foundation

nonisolated enum SwiftProjectError: LocalizedError, Sendable {
    case invalidRoot
    case missingSwiftDirectory
    case missingBuildScript
    case missingUpdateCheckout
    case noBuildSubdirectory
    case directoryListingFailed(path: String, underlying: String)
    case resourceLookupFailed(path: String, underlying: String)

    var errorDescription: String? {
        switch self {
        case .invalidRoot: "Select a directory that contains the swift checkout."
        case .missingSwiftDirectory: "Could not find swift/ inside the selected directory."
        case .missingBuildScript: "Could not find swift/utils/build-script."
        case .missingUpdateCheckout: "Could not find swift/utils/update-checkout."
        case .noBuildSubdirectory: "No Ninja build directory found under build/."
        case let .directoryListingFailed(path, underlying):
            "Could not list contents of \(path): \(underlying)"
        case let .resourceLookupFailed(path, underlying):
            "Could not read file properties for \(path): \(underlying)"
        }
    }
}
