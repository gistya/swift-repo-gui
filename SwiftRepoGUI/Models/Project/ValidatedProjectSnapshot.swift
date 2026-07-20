import Foundation

nonisolated public struct ValidatedProjectSnapshot: Sendable, Equatable {
    public let root: URL
    public let swiftDirectory: URL
    public let buildScript: URL
    public let updateCheckout: URL
    public let buildRoot: URL
    public let candidates: [RepositoryCandidate]
    public let detectedBuildSubdirs: [String]
    public let swiftBuildDirectoryName: String
    public let checkoutScheme: String
    public let swiftBranch: String
    public let schemeResolutionSource: SchemeResolutionSource
    public let availableCheckoutSchemes: [String]
}
