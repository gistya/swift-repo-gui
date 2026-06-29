import SwiftUI
import SwiftXStateSwiftUI

/// Narrow view: only observes build progress fields, not project/settings context.
struct BuildProgressPanel: View {
    let build: MachineStore<BuildOperationsMachine>

    var body: some View {
        GroupBox("Active Build") {
            if build.matches(.running) {
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(value: build.context.progress.fraction) {
                        Text("Building… \(Int(build.context.progress.fraction * 100))%")
                    }
                    if let eta = build.context.progress.etaSeconds, eta > 0 {
                        Text("ETA: \(formatDuration(eta))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if build.context.progress.totalSteps > 0 {
                        Text("\(build.context.progress.completedSteps) / \(build.context.progress.totalSteps) ninja steps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let job = build.context.activeJob {
                        Text(job.displayCommand)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack {
                        Button("Cancel", role: .destructive) { build.send(.cancel) }
                        Spacer()
                        Button("Open Logs Folder") { NSWorkspace.shared.open(AppPaths.logsDirectory) }
                    }
                }
            } else if let message = build.context.statusMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView(
                    "No Active Build",
                    systemImage: "hammer",
                    description: Text("Start a build from the actions above.")
                )
                .frame(maxHeight: 120)
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds > 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "\(Int(seconds))s"
    }
}

import AppKit