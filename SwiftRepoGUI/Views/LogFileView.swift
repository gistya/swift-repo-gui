import AppKit
import SwiftUI

/// Reads build logs from disk with throttled polling — keeps log text out of machine context.
struct LogFileView: View {
    let operationID: UUID
    let fallback: String

    @State private var reader = LogTailReader()
    @State private var autoScroll = true

    var body: some View {
        GroupBox("Build Log") {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(reader.text.isEmpty ? fallback : reader.text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("log-bottom")
                }
                .frame(minHeight: 240)
                .onChange(of: reader.text) {
                    if autoScroll {
                        proxy.scrollTo("log-bottom", anchor: .bottom)
                    }
                }
            }
            HStack {
                Toggle("Auto-scroll", isOn: $autoScroll)
                Spacer()
                Button("Reveal in Finder") { revealLog() }
                Button("Refresh") { reader.reload() }
            }
            .font(.caption)
        }
        .onAppear {
            reader.track(url: AppPaths.logFileURL(for: operationID))
        }
        .onDisappear { reader.stop() }
    }

    private func revealLog() {
        let url = AppPaths.logFileURL(for: operationID)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(AppPaths.logsDirectory)
        }
    }
}