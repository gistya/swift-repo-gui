import Foundation
import SwiftXState

nonisolated public struct ProjectContext: Sendable, Equatable {
    public var projectPath: String = UserDefaults.standard.string(forKey: "projectPath") ?? ""
    public var selectedBuildSubdir: String = UserDefaults.standard.string(forKey: "selectedBuildSubdir") ?? ""
    public var checkoutSchemeOverride: String = UserDefaults.standard.string(forKey: "checkoutSchemeOverride") ?? ""
    public var projectInfo: SwiftProjectInfo?
    public var validationMessage: String?
    public var revisionsBeforeUpdate: [String: String] = [:]
    public var inspectMode: ProjectInspectMode = .fullInspect
    public var reloadPending: Bool = false

    public var isValid: Bool { projectInfo != nil }
}
