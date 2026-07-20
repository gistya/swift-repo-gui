import SwiftXState

nonisolated public enum ProjectEvent: EventIdentifying {
    case setPath(String)
    case setBuildSubdir(String)
    case setCheckoutSchemeOverride(String)
    case refresh
    case captureRevisions
    case restore
    public static var _blank: ProjectEvent { .refresh }
}
