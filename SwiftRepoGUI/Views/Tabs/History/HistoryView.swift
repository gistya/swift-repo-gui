import AppKit
import SwiftUI
import SwiftData
import SwiftXStateSwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    let session: AppSession
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BuildOperationRecord.createdAt, order: .reverse) private var operations: [BuildOperationRecord]

    @State private var selectedOperationID: UUID?
    @State private var importError: String?

    var body: some View {
        NavigationSplitView {
            List(operations, selection: $selectedOperationID) { operation in
                HistoryRow(operation: operation)
                    .tag(operation.id)
            }
            .scrollContentBackground(.hidden)
            .background(TerminalBackground())
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
            .toolbar {
                ToolbarItemGroup {
                    Button("Import…") { importOperationFromDisk() }
                        .accessibilityLabel("Import Operation")
                        .accessibilityHint("Opens a picker to import a build operation from a .swiftbuildop file.")
                    ActionHelpButton("action.import")
                        .accessibilityLabel("Help about Import Operation")
                    Button("Open Logs") { AppFolderActions.openLogsFolder() }
                        .accessibilityLabel("Open Logs Folder")
                        .accessibilityHint("Reveals the build logs folder in Finder.")
                    ActionHelpButton("action.openLogsFolder")
                        .accessibilityLabel("Help about Open Logs Folder")
                    Button("Open Exports") { AppFolderActions.openExportsFolder() }
                        .accessibilityLabel("Open Exports Folder")
                        .accessibilityHint("Reveals the exported operations folder in Finder.")
                    ActionHelpButton("action.openExportsFolder")
                        .accessibilityLabel("Help about Open Exports Folder")
                }
            }
        } detail: {
            if let operation = selectedOperation {
                OperationDetailView(operation: operation, session: session)
            } else {
                ContentUnavailableView(
                    "Select an Operation",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Pick a past build to inspect logs, replay, or export.")
                )
            }
        }
        .background(TerminalBackground())
        .terminalText()
        .navigationTitle("History")
        .alert("Import Error", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
                .accessibilityLabel("OK")
                .accessibilityHint("Dismisses the import error.")
        } message: {
            Text(importError ?? "")
        }
    }

    private var selectedOperation: BuildOperationRecord? {
        guard let selectedOperationID else { return operations.first }
        return operations.first { $0.id == selectedOperationID }
    }

    private func importOperationFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [OperationImportExport.operationUTType, .json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let imported = try OperationImportExport.importOperation(from: data)
            Task {
                do {
                    try await session.applyImportedProject(
                        path: imported.projectPath,
                        buildSubdir: imported.buildSubdir,
                        options: imported.options,
                        targetRepository: imported.targetRepository
                    )
                } catch {
                    importError = error.localizedDescription
                    return
                }
                let record = BuildOperationRecord(
                    kind: imported.kind,
                    projectPath: imported.projectPath,
                    buildSubdir: imported.buildSubdir,
                    targetRepository: imported.targetRepository,
                    commandLine: imported.commandLine,
                    logFileName: "",
                    options: imported.options,
                    notes: String(
                        format: NSLocalizedString("Imported: %@", comment: "Prefix for the notes of an imported build operation"),
                        imported.notes
                    ),
                    savedProfileName: imported.savedProfileName
                )
                modelContext.insert(record)
                selectedOperationID = record.id
            }
        } catch {
            importError = error.localizedDescription
        }
    }
}
