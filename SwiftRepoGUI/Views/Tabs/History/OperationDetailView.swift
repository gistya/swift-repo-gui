import SwiftRepoCore
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
        GroupBox {
            Text(operation.commandLine)
                .font(.monaco(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Command")
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("Replay") {
                Task { await session.replay(operation) }
            }
            .disabled(session.build.matches(.running))
            .accessibilityLabel("Replay Operation")
            .accessibilityHint("Restores this operation's settings and runs the build again. Disabled while a build is running.")
            ActionHelpButton("action.replay")
                .accessibilityLabel("Help about Replay Operation")

            Button(copied ? "Copied!" : "Copy Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(shellWrappedCommand, forType: .string)
                copied = true
            }
            .accessibilityLabel("Copy Command Line")
            .accessibilityHint("Copies this operation's shell command to the clipboard.")
            ActionHelpButton("action.copyCommand")
                .accessibilityLabel("Help about Copy Command Line")

            Button("Export…") { exportOperation() }
                .accessibilityLabel("Export Operation")
                .accessibilityHint("Writes this operation to a .swiftbuildop file and reveals it in Finder.")
            ActionHelpButton("action.export")
                .accessibilityLabel("Help about Export Operation")
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
            exportMessage = String(
                format: NSLocalizedString("Exported to %@", comment: "Confirmation shown after exporting an operation, with the file name"),
                url.lastPathComponent
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            exportMessage = error.localizedDescription
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: interval) ?? String(
            format: NSLocalizedString("%ds", comment: "Fallback duration format in seconds"),
            Int(interval)
        )
    }
}
