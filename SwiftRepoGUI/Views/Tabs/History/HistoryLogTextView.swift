import AppKit
import Matrix
import SwiftUI

/// Loads completed build logs once, off the main actor, and keeps full text out of State snapshots.
struct HistoryLogFileView: View {
    let operationID: UUID
    let logFileName: String?
    let fallback: String

    @State private var loader = HistoryLogLoader()

    init(operationID: UUID, logFileName: String? = nil, fallback: String) {
        self.operationID = operationID
        self.logFileName = logFileName
        self.fallback = fallback
    }

    var body: some View {
        GroupBox("Build Log") {
            ZStack {
                if loader.isLoading {
                    loadingView
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    LogTextView(text: loader.displayText, scroll: .top)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
            }
            .animation(.easeInOut(duration: 0.24), value: loader.isLoading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .terminalText()
        .task(id: logIdentity) {
            do {
                try await loader.load(url: logURL(), fallback: fallback)
            } catch {
                loader.fail(localizedErrorMessage(for: error), fallback: fallback)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            MatrixLoader(.fun(.snake), size: 32.0, color: .terminalGreen, speed: 10.0, bloom: true, halo: 4.0)
            Text("Loading Log...")
                .font(.monaco(size: 13, weight: .bold))
                .foregroundStyle(Color.terminalGreen)
                .shadow(color: Color.terminalGreen.opacity(0.75), radius: 5)
            Text(logDisplayName)
                .font(.monaco(size: 10))
                .foregroundStyle(Color.terminalGreen.opacity(0.62))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 6))
    }

    private var logIdentity: String {
        "\(operationID.uuidString)-\(logFileName ?? "")"
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


