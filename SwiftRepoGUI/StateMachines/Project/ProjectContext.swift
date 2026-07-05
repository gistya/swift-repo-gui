import Foundation
import SwiftXState

nonisolated struct ProjectContext: Sendable, Equatable {
    var projectPath: String = UserDefaults.standard.string(forKey: "projectPath") ?? ""
    var selectedBuildSubdir: String = UserDefaults.standard.string(forKey: "selectedBuildSubdir") ?? ""
    var checkoutSchemeOverride: String = UserDefaults.standard.string(forKey: "checkoutSchemeOverride") ?? ""
    var projectInfo: SwiftProjectInfo?
    var validationMessage: String?
    var revisionsBeforeUpdate: [String: String] = [:]
    var inspectMode: ProjectInspectMode = .fullInspect
    var reloadPending: Bool = false

    var isValid: Bool { projectInfo != nil }
}
