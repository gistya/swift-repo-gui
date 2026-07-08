import AppKit
import SwiftRepoCore
import SwiftUI
import SwiftXStateSwiftUI

/// Narrow view: only observes build progress fields, not project/settings context.
struct BuildProgressPanel: View {
    let build: MachineStore<BuildOperationsMachine>
    @State private var copiedFailureReason = false

    var body: some View {
        GroupBox("Active Build") {
            if build.matches(.running) {
                VStack(alignment: .leading, spacing: 10) {
                    if hasActiveNinjaProgress {
                        ProgressView(value: build.context.progress.fraction) {
                            Text("Building... \(Int(build.context.progress.fraction * 100))%")
                        }
                        .accessibilityLabel("Build progress")
                        .accessibilityValue("\(Int(build.context.progress.fraction * 100)) percent")
                    } else {
                        ProgressView {
                            Text(runningTitle)
                        }
                        .accessibilityLabel(runningTitle)
                    }
                    if let eta = build.context.progress.etaSeconds, eta > 0 {
                        Text("ETA: \(formatDuration(eta))")
                            .font(.monaco(size: 11))
                            .foregroundStyle(Color.terminalGreen.opacity(0.75))
                            .accessibilityLabel("Estimated time remaining: \(formatDuration(eta))")
                    }
                    if build.context.progress.totalSteps > 0 {
                        Text("\(build.context.progress.completedSteps) / \(build.context.progress.totalSteps) ninja steps")
                            .font(.monaco(size: 11))
                            .foregroundStyle(Color.terminalGreen.opacity(0.75))
                            .accessibilityLabel("\(build.context.progress.completedSteps) of \(build.context.progress.totalSteps) ninja steps completed")
                    }
                    if let message = build.context.progress.message, !message.isEmpty {
                        Text(message)
                            .font(.monaco(size: 11))
                            .foregroundStyle(Color.terminalGreen.opacity(0.75))
                            .lineLimit(3)
                    }
                    if let job = build.context.activeJob {
                        Text(job.displayCommand)
                            .font(.monaco(size: 10))
                            .foregroundStyle(Color.terminalGreen.opacity(0.75))
                            .lineLimit(2)
                            .accessibilityLabel("Current command: \(job.displayCommand)")
                    }
                    HStack {
                        Button("Cancel", role: .destructive) { build.send(.cancel) }
                            .accessibilityLabel("Cancel build")
                            .accessibilityHint("Stops the running build.")
                        ActionHelpButton("action.cancel")
                            .accessibilityLabel("Help about Cancel build")
                        Spacer()
                        Button("Open Logs Folder") { AppFolderActions.openLogsFolder() }
                            .accessibilityLabel("Open logs folder")
                            .accessibilityHint("Reveals the build logs folder in Finder.")
                        ActionHelpButton("action.openLogsFolder")
                            .accessibilityLabel("Help about Open logs folder")
                    }
                }
            } else if let message = build.context.statusMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Text(message)
                        .font(.monaco(size: 13))
                        .foregroundStyle(statusColor(for: message).opacity(0.82))
                        .textSelection(.enabled)
                    if canCopyFailureReason(message) {
                        HStack {
                            Button(copiedFailureReason ? "Copied Failure Reason" : "Copy Failure Reason") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message, forType: .string)
                                copiedFailureReason = true
                            }
                            .accessibilityLabel(copiedFailureReason ? "Copied failure reason" : "Copy failure reason")
                            .accessibilityHint("Copies the build failure message to the clipboard.")
                            ActionHelpButton("action.copyFailureReason")
                                .accessibilityLabel("Help about Copy failure reason")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView(
                    "No Active Build",
                    systemImage: "hammer",
                    description: Text("Start a build from the actions above.")
                )
                .frame(maxHeight: 120)
            }
        }
        .onChange(of: build.context.statusMessage) {
            copiedFailureReason = false
        }
    }

    private var runningTitle: String {
        guard let job = build.context.activeJob else { return "Running..." }
        return "Running \(job.kind.title)..."
    }

    private var hasActiveNinjaProgress: Bool {
        let progress = build.context.progress
        return progress.totalSteps > 0 && progress.completedSteps < progress.totalSteps
    }

    private func formatDuration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds > 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "\(Int(seconds))s"
    }

    private func canCopyFailureReason(_ message: String) -> Bool {
        guard let exitCode = build.context.lastExitCode else { return false }
        return exitCode != 0 && message != "Build cancelled."
    }

    private func statusColor(for message: String) -> Color {
        canCopyFailureReason(message) ? .terminalFailureRed : .terminalGreen
    }
}
