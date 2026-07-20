public enum BuildOptionCategory: String, CaseIterable, Identifiable, Sendable {
    case buildMode
    case swiftComponents
    case platformTargets
    case performance
    case sanitizers
    case testing
    case products
    case installation
    case deployment
    case paths
    case advanced

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .buildMode: "Build Mode"
        case .swiftComponents: "Swift Components"
        case .platformTargets: "Platform Targets"
        case .performance: "Performance"
        case .sanitizers: "Sanitizers"
        case .testing: "Testing"
        case .products: "Products"
        case .installation: "Installation"
        case .deployment: "Host & Deployment"
        case .paths: "Paths & CMake"
        case .advanced: "Advanced"
        }
    }
}
