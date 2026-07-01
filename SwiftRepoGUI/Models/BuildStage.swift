import Foundation

nonisolated enum BuildStage: String, CaseIterable, Sendable, Equatable, Hashable {
    case off
    case building
    case testing
    case measuring
    case deploying
    case failed

    var title: String {
        switch self {
        case .off: String(localized: "OFF")
        case .building: String(localized: "BUILDING")
        case .testing: String(localized: "TESTING")
        case .measuring: String(localized: "MEASURING")
        case .deploying: String(localized: "DEPLOYING")
        case .failed: String(localized: "FAILED")
        }
    }

    var isActive: Bool {
        self != .off
    }

    static func stage(for context: BuildOperationsContext) -> BuildStage {
        if !context.isRunning {
            if let exitCode = context.lastExitCode, exitCode != 0 {
                return .failed
            }
            if let status = context.statusMessage?.lowercased(),
               status.contains("failed") || status.contains("error") {
                return .failed
            }
            return .off
        }

        guard let job = context.activeJob else { return .building }
        let text = [
            job.kind.rawValue,
            job.displayCommand,
            context.progress.message ?? "",
            job.targetRepository
        ]
            .joined(separator: " ")
            .lowercased()

        if text.contains("test") || text.contains("lit ") || text.contains("validation") {
            return .testing
        }
        if text.contains("benchmark") || text.contains("measure") || text.contains("perf") {
            return .measuring
        }
        if text.contains("install") ||
            text.contains("package") ||
            text.contains("deploy") ||
            text.contains("updatecheckout") ||
            text.contains("update-checkout") {
            return .deploying
        }
        return .building
    }

    static func moduleDisplay(for context: BuildOperationsContext) -> String {
        if stage(for: context) == .failed { return String(localized: "ERROR") }
        guard context.isRunning else { return String(localized: "READY") }
        if let message = context.progress.message,
           let module = moduleName(from: message) {
            return module
        }
        if let target = context.activeJob?.targetRepository, !target.isEmpty {
            return clipped(target.uppercased(), limit: 22)
        }
        return clipped(context.activeJob?.kind.title.uppercased() ?? String(localized: "RUNNING"), limit: 22)
    }

    private static func moduleName(from message: String) -> String? {
        var text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let closeBracket = text.firstIndex(of: "]") {
            text = String(text[text.index(after: closeBracket)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for marker in ["Building ", "Compiling ", "Linking ", "Installing ", "Testing "] {
            if let range = text.range(of: marker, options: [.caseInsensitive]) {
                text = String(text[range.upperBound...])
                break
            }
        }

        if let pathToken = text.split(whereSeparator: \.isWhitespace).first(where: { $0.contains("/") }) {
            let lastComponent = String(pathToken).split(separator: "/").last.map(String.init)
            if let lastComponent, !lastComponent.isEmpty {
                text = lastComponent
            }
        }

        let cleaned = text
            .replacingOccurrences(of: ".build/", with: "")
            .replacingOccurrences(of: ".o", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .:/\\"))
        guard !cleaned.isEmpty else { return nil }
        return clipped(cleaned.uppercased(), limit: 22)
    }

    private static func clipped(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit - 1)) + "…"
    }
}
