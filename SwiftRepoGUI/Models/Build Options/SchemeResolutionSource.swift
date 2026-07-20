nonisolated public enum SchemeResolutionSource: String, Sendable, Equatable, Hashable {
    case manualOverride
    case branchName
    case alias
    case swiftRepoBranch
    case defaultScheme
    case branchFallback

    public var explanation: String {
        switch self {
        case .manualOverride:
            "Using your manually selected checkout scheme."
        case .branchName:
            "Matched the current swift branch name to a checkout scheme."
        case .alias:
            "Matched the current swift branch to a scheme alias."
        case .swiftRepoBranch:
            "Matched a scheme whose swift repo branch equals your current branch."
        case .defaultScheme:
            "Could not read the current swift branch; using the default scheme from update-checkout-config.json."
        case .branchFallback:
            "No configured scheme matched the current swift branch; using the branch name as the update-checkout scheme."
        }
    }
}
