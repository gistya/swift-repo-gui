import CompositionalInit
import Foundation

nonisolated struct SwiftProjectInfo: Sendable, Equatable, Hashable, Blankable {
    let root: URL
    let swiftDirectory: URL
    let buildScript: URL
    let updateCheckout: URL
    let buildRoot: URL
    let repositories: [SwiftRepository]
    let detectedBuildSubdirs: [String]
    let swiftBuildDirectoryName: String
    let checkoutScheme: String
    let swiftBranch: String
    let schemeResolutionSource: SchemeResolutionSource
    let availableCheckoutSchemes: [String]

    func replacingRepositories(_ repositories: [SwiftRepository]) -> SwiftProjectInfo {
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
    
    static let _blank = Self(
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
