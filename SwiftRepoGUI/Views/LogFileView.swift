import AppKit
import SwiftUI

/// Reads build logs from disk with throttled polling — keeps log text out of machine context.
struct LogFileView: View {
    let operationID: UUID
    let logFileName: String?
    let fallback: String

    @State private var reader = LogTailReader()
    @State private var autoScroll = true
    @State private var setupError: String?

    init(operationID: UUID, logFileName: String? = nil, fallback: String) {
        self.operationID = operationID
        self.logFileName = logFileName
        self.fallback = fallback
    }

    var body: some View {
        GroupBox("Build Log") {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let setupError {
                            Label(setupError, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Color.terminalGreen)
                                .font(.monaco(size: 13))
                        }
                        if let readError = reader.readError {
                            Label(readError, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Color.terminalGreen)
                                .font(.monaco(size: 13))
                        }
                        if reader.isWaitingForFile {
                            Label("Waiting for log file \(logDisplayName).", systemImage: "clock")
                                .foregroundStyle(Color.terminalGreen.opacity(0.75))
                                .font(.monaco(size: 13))
                        }
                        if !reader.visibleByteDescription.isEmpty {
                            Label(reader.visibleByteDescription, systemImage: reader.isShowingTail ? "text.append" : "doc.text")
                                .foregroundStyle(Color.terminalGreen.opacity(reader.isShowingTail ? 1 : 0.75))
                                .font(.monaco(size: 13))
                        }
                        Text(displayText)
                            .font(.monaco(size: 11))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("log-bottom")
                    }
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
                Button("Open Log") { openLog() }
                ActionHelpButton("action.openLog")
                Button("Reveal in Finder") { revealLog() }
                ActionHelpButton("action.revealLog")
                Button("Refresh") { reader.reload() }
                ActionHelpButton("action.refreshLog")
            }
            .font(.monaco(size: 11))
            .foregroundStyle(Color.terminalGreen)
        }
        .terminalText()
        .onAppear(perform: startTracking)
        .onDisappear { reader.stop() }
    }

    private var displayText: String {
        if !reader.text.isEmpty { return reader.text }
        if setupError != nil || reader.readError != nil { return fallback }
        return reader.text.isEmpty ? fallback : reader.text
    }

    private func startTracking() {
        do {
            setupError = nil
            reader.track(url: try logURL())
        } catch {
            reader.stop()
            setupError = error.localizedDescription
        }
    }

    private func revealLog() {
        do {
            let url = try logURL()
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                AppFolderActions.openLogsFolder()
            }
        } catch {
            setupError = error.localizedDescription
        }
    }

    private func openLog() {
        do {
            let url = try logURL()
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.open(url)
            } else {
                AppFolderActions.openLogsFolder()
            }
        } catch {
            setupError = error.localizedDescription
        }
    }

    private func logURL() throws -> URL {
        if let logFileName {
            return try AppPaths.logFileURL(named: logFileName)
        }
        return try AppPaths.logFileURL(for: operationID)
    }

    private var logDisplayName: String {
        if let logFileName, !logFileName.isEmpty {
            return URL(fileURLWithPath: logFileName).lastPathComponent
        }
        return "\(operationID.uuidString).log"
    }
}
