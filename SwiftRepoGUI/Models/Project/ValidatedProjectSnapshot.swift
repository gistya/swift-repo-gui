import Foundation

nonisolated struct ValidatedProjectSnapshot: Sendable, Equatable {
    let root: URL
    let swiftDirectory: URL
    let buildScript: URL
    let updateCheckout: URL
    let buildRoot: URL
    let candidates: [RepositoryCandidate]
    let detectedBuildSubdirs: [String]
    let swiftBuildDirectoryName: String
    let checkoutScheme: String
    let swiftBranch: String
    let schemeResolutionSource: SchemeResolutionSource
    let availableCheckoutSchemes: [String]
}
