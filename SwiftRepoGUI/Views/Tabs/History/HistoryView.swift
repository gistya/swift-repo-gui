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
    // Two-step delete flow: first "are you sure", then (only if a log exists) "delete the log too?".
    @State private var operationPendingDeletion: BuildOperationRecord?
    @State private var operationPendingLogChoice: BuildOperationRecord?

    var body: some View {
        NavigationSplitView {
            List(operations, selection: $selectedOperationID) { operation in
                HistoryRow(operation: operation)
                    .tag(operation.id)
                    .contextMenu {
                        Button(role: .destructive) {
                            operationPendingDeletion = operation
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .accessibilityHint("Deletes this build operation from history.")
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            operationPendingDeletion = operation
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .scrollContentBackground(.hidden)
            .background(TerminalBackground())
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
            .onDeleteCommand {
                if let target = selectedOperation {
                    operationPendingDeletion = target
                }
            }
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
        // Step 1 — "are you sure?"
        .confirmationDialog(
            "Delete this operation?",
            isPresented: Binding(
                get: { operationPendingDeletion != nil },
                set: { if !$0 { operationPendingDeletion = nil } }
            ),
            presenting: operationPendingDeletion
        ) { operation in
            Button("Delete", role: .destructive) {
                operationPendingDeletion = nil
                // Only bother asking about logs if there is actually a log file on disk.
                if logFileExists(for: operation) {
                    operationPendingLogChoice = operation
                } else {
                    deleteOperation(operation, deletingLog: false)
                }
            }
            Button("Cancel", role: .cancel) { operationPendingDeletion = nil }
        } message: { operation in
            Text("Remove the \(operation.kind.title) operation from \(operation.createdAt.formatted(date: .abbreviated, time: .shortened)) from history? This can’t be undone.")
        }
        // Step 2 — "delete the associated log too?" (only shown when a log file exists)
        .confirmationDialog(
            "Delete the associated log too?",
            isPresented: Binding(
                get: { operationPendingLogChoice != nil },
                set: { if !$0 { operationPendingLogChoice = nil } }
            ),
            presenting: operationPendingLogChoice
        ) { operation in
            Button("Delete Operation and Log", role: .destructive) {
                deleteOperation(operation, deletingLog: true)
                operationPendingLogChoice = nil
            }
            Button("Delete Operation, Keep Log") {
                deleteOperation(operation, deletingLog: false)
                operationPendingLogChoice = nil
            }
            Button("Cancel", role: .cancel) { operationPendingLogChoice = nil }
        } message: { operation in
            Text("The log file “\(operation.logFileName)” will be permanently deleted along with the operation.")
        }
    }

    private var selectedOperation: BuildOperationRecord? {
        guard let selectedOperationID else { return operations.first }
        return operations.first { $0.id == selectedOperationID }
    }

    // MARK: - Delete

    private func deleteOperation(_ operation: BuildOperationRecord, deletingLog: Bool) {
        if deletingLog { deleteLogFile(for: operation) }
        if selectedOperationID == operation.id { selectedOperationID = nil }
        modelContext.delete(operation)
    }

    private func deleteLogFile(for operation: BuildOperationRecord) {
        guard let url = logFileURL(for: operation),
              FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func logFileExists(for operation: BuildOperationRecord) -> Bool {
        guard let url = logFileURL(for: operation) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// The record's log file, resolved strictly inside our own logs directory (by last path
    /// component) so a delete can never touch a file outside it. `nil` when the record has no log
    /// (e.g. an imported operation with an empty `logFileName`).
    private func logFileURL(for operation: BuildOperationRecord) -> URL? {
        let trimmed = operation.logFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let safeName = URL(fileURLWithPath: trimmed).lastPathComponent
        guard !safeName.isEmpty, let logsDirectory = try? AppPaths.logsDirectory() else { return nil }
        return logsDirectory.appendingPathComponent(safeName)
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
