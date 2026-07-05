import SwiftUI
import SwiftXStateSwiftUI

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
