import SwiftXState

nonisolated enum ProjectEvent: EventIdentifying {
    case setPath(String)
    case setBuildSubdir(String)
    case setCheckoutSchemeOverride(String)
    case refresh
    case captureRevisions
    case restore
    static var _blank: ProjectEvent { .refresh }
}
