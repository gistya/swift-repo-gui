import AppKit
import SwiftRepoCore
import SwiftUI
import SwiftData
import SwiftXStateSwiftUI

struct LiveLogView: View {
    let build: MachineStore<BuildOperationsMachine>
    @Query(sort: \BuildOperationRecord.createdAt, order: .reverse) private var operations: [BuildOperationRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if build.matches(.running), let job = build.context.activeJob {
                LogFileView(operationID: job.operationID, fallback: job.displayCommand)
                    .padding()
            } else if let latest = operations.first {
                LogFileView(operationID: latest.id, logFileName: latest.logFileName, fallback: latest.commandLine)
                    .padding()
            } else {
                ContentUnavailableView("No Logs Yet", systemImage: "doc.text", description: Text("Run a build to capture output here."))
            }
        }
        .background(TerminalBackground())
        .terminalText()
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItemGroup {
                Button("Open Logs Folder") { AppFolderActions.openLogsFolder() }
                    .accessibilityLabel("Open Logs Folder")
                    .accessibilityHint("Opens the folder containing saved build logs in Finder.")
                ActionHelpButton("action.openLogsFolder")
                Button("Open Exports Folder") { AppFolderActions.openExportsFolder() }
                    .accessibilityLabel("Open Exports Folder")
                    .accessibilityHint("Opens the folder containing exported files in Finder.")
                ActionHelpButton("action.openExportsFolder")
            }
        }
    }
}
