import AppKit
import Foundation
import SwiftRepoCore

@MainActor
enum AppFolderActions {
    static func openLogsFolder() {
        openFolder(trying: AppPaths.logsDirectory)
    }

    static func openExportsFolder() {
        openFolder(trying: AppPaths.exportsDirectory)
    }

    private static func openFolder(trying makeURL: () throws -> URL) {
        do {
            NSWorkspace.shared.open(try makeURL())
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could Not Open Folder"
            alert.informativeText = localizedErrorMessage(for: error)
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
