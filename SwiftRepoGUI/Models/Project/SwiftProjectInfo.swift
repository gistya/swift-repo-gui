import CompositionalInit
import Foundation

nonisolated public struct SwiftProjectInfo: Sendable, Equatable, Hashable, Blankable {
    public let root: URL
    public let swiftDirectory: URL
    public let buildScript: URL
    public let updateCheckout: URL
    public let buildRoot: URL
    public let repositories: [SwiftRepository]
    public let detectedBuildSubdirs: [String]
    public let swiftBuildDirectoryName: String
    public let checkoutScheme: String
    public let swiftBranch: String
    public let schemeResolutionSource: SchemeResolutionSource
    public let availableCheckoutSchemes: [String]

    public func replacingRepositories(_ repositories: [SwiftRepository]) -> SwiftProjectInfo {
        SwiftProjectInfo(
            root: root,
            swiftDirectory: swiftDirectory,
            buildScript: buildScript,
            updateCheckout: updateCheckout,
            buildRoot: buildRoot,
            repositories: repositories,
            detectedBuildSubdirs: detectedBuildSubdirs,
            swiftBuildDirectoryName: swiftBuildDirectoryName,
            checkoutScheme: checkoutScheme,
            swiftBranch: swiftBranch,
            schemeResolutionSource: schemeResolutionSource,
            availableCheckoutSchemes: availableCheckoutSchemes
        )
    }
    
    public static let _blank = Self(
        root: ._blank,
        swiftDirectory: ._blank,
        buildScript: ._blank,
        updateCheckout: ._blank,
        buildRoot: ._blank,
        repositories: [],
        detectedBuildSubdirs: [],
        swiftBuildDirectoryName: ._blank,
        checkoutScheme: ._blank,
        swiftBranch: ._blank,
        schemeResolutionSource: .alias,
        availableCheckoutSchemes: []
    )
}
