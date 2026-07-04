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
                    ActionHelpButton("action.import")
                    Button("Open Logs") { AppFolderActions.openLogsFolder() }
                    ActionHelpButton("action.openLogsFolder")
                    Button("Open Exports") { AppFolderActions.openExportsFolder() }
                    ActionHelpButton("action.openExportsFolder")
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
                    notes: "Imported: \(imported.notes)",
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

struct HistoryRow: View {
    let operation: BuildOperationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: operation.kind.symbolName)
                Text(operation.kind.title)
                    .font(.monaco(size: 13, weight: .bold))
                Spacer()
                statusBadge
            }
            Text(operation.createdAt, style: .date)
                .font(.monaco(size: 10))
                .foregroundStyle(Color.terminalGreen.opacity(0.75))
            if !operation.targetRepository.isEmpty {
                Text(operation.targetRepository)
                    .font(.monaco(size: 11))
                    .foregroundStyle(Color.terminalGreen.opacity(0.75))
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        let badgeColor = operation.status == .failed ? Color.terminalFailureRed : Color.terminalGreen
        Text(operation.status.title)
            .font(.monaco(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor)
    }
}

struct OperationDetailView: View {
    let operation: BuildOperationRecord
    let session: AppSession

    @State private var copied = false
    @State private var exportMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    commandSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 230)

            HistoryLogFileView(operationID: operation.id, logFileName: operation.logFileName, fallback: operation.commandLine)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            actionButtons
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(operation.kind.title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Status", value: operation.status.title)
            LabeledContent("Started", value: operation.createdAt.formatted())
            if let finished = operation.finishedAt {
                LabeledContent("Finished", value: finished.formatted())
            }
            if let duration = operation.duration {
                LabeledContent("Duration", value: formatDuration(duration))
            }
            if let code = operation.exitCode {
                LabeledContent("Exit Code", value: String(code))
            }
            LabeledContent("Project", value: operation.projectPath)
            LabeledContent("Build Dir", value: operation.buildSubdir)
        }
        .font(.monaco(size: 13))
    }

    private var commandSection: some View {
        GroupBox("Command") {
            Text(operation.commandLine)
                .font(.monaco(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("Replay") {
                Task { await session.replay(operation) }
            }
            .disabled(session.build.matches(.running))
            ActionHelpButton("action.replay")

            Button(copied ? "Copied!" : "Copy Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(shellWrappedCommand, forType: .string)
                copied = true
            }
            ActionHelpButton("action.copyCommand")

            Button("Export…") { exportOperation() }
            ActionHelpButton("action.export")
            Spacer()
            if let exportMessage {
                Text(exportMessage)
                    .font(.monaco(size: 11))
                    .foregroundStyle(Color.terminalGreen.opacity(0.75))
            }
        }
    }

    private var shellWrappedCommand: String {
        if operation.commandLine.contains("cd ") {
            return operation.commandLine
        }
        return "cd \(BuildCommandBuilder.shellQuote(operation.projectPath)) && \(operation.commandLine)"
    }

    private func exportOperation() {
        do {
            let exported = ExportedBuildOperation(from: operation)
            let url = try OperationImportExport.writeExportFile(exported)
            exportMessage = "Exported to \(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            exportMessage = error.localizedDescription
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: interval) ?? "\(Int(interval))s"
    }
}
