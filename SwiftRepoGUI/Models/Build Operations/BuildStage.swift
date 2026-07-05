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
            if context.statusMessage == "Build cancelled." {
                return .off
            }
            if let exitCode = context.lastExitCode, exitCode != 0 {
                return .failed
            }
            if let status = context.statusMessage?.lowercased(),
               status.contains("failed") || status.contains("error") {
                return .failed
            }
            return .off
        }

        return runningStage(for: context.activeJob, progress: context.progress)
    }

    static func stage(for state: BuildOpsState, context: BuildOperationsContext) -> BuildStage {
        switch state {
        case .building, .running:
            .building
        case .testing:
            .testing
        case .measuring:
            .measuring
        case .deploying:
            .deploying
        case .error:
            .failed
        case .cancelled:
            .off
        case .idle, .completed:
            stage(for: context)
        }
    }

    static func runningStage(
        for job: BuildJob?,
        progress: BuildProgressSnapshot
    ) -> BuildStage {
        guard let job else { return .building }
        let text = [
            job.kind.rawValue,
            job.displayCommand,
            progress.message ?? "",
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
           let target = primaryTarget(from: message) {
            return clipped(target, limit: 22)
        }
        if let target = context.activeJob?.targetRepository, !target.isEmpty {
            return clipped(target, limit: 22)
        }
        return clipped(context.activeJob?.kind.title ?? String(localized: "RUNNING"), limit: 22)
    }

    static func moduleDisplay(for stage: BuildStage, context: BuildOperationsContext) -> String {
        if stage == .failed { return String(localized: "ERROR") }
        guard stage.isActive else { return String(localized: "READY") }
        if let message = context.progress.message,
           let target = primaryTarget(from: message) {
            return clipped(target, limit: 22)
        }
        if let target = context.activeJob?.targetRepository, !target.isEmpty {
            return clipped(target, limit: 22)
        }
        return clipped(context.activeJob?.kind.title ?? String(localized: "RUNNING"), limit: 22)
    }

    private static func primaryTarget(from message: String) -> String? {
        var text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let closeBracket = text.firstIndex(of: "]") {
            text = String(text[text.index(after: closeBracket)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let quotedModule = firstRegexCapture(#"(?:module|target)\s+['"]([^'"]+)['"]"#, in: text) {
            return cleanedTargetName(quotedModule)
        }

        if let pathTarget = targetFromPath(in: text) {
            return pathTarget
        }

        if let linkedTarget = firstRegexCapture(#"(?:Linking|Creating)\s+.*(?:/|\s)(?:lib)?([A-Za-z0-9_+.-]+)\.(?:a|dylib|so|tbd|exe)"#, in: text),
           let cleaned = cleanedTargetName(linkedTarget) {
            return cleaned
        }

        let ignoredTokens: Set<String> = [
            "building", "compiling", "linking", "installing", "testing",
            "c", "cxx", "swift", "object", "objects", "module", "library", "executable",
            "static", "shared", "archive", "tablegen"
        ]
        let tokens = text
            .replacingOccurrences(of: ":", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        for token in tokens {
            let lower = token.trimmingCharacters(in: .punctuationCharacters).lowercased()
            guard !ignoredTokens.contains(lower),
                  !lower.hasPrefix("-"),
                  !lower.contains("="),
                  let cleaned = cleanedTargetName(token) else { continue }
            if !cleaned.contains(".") {
                return cleaned
            }
        }

        return nil
    }

    private static func targetFromPath(in text: String) -> String? {
        let knownTargets = [
            "libcxx", "libcxxabi", "compiler-rt", "clang", "lld", "lldb", "llvm",
            "swift", "swiftpm", "swift-driver", "swift-syntax", "sourcekit-lsp",
            "foundation", "xctest", "llbuild", "cmark", "dispatch"
        ]

        for rawToken in text.split(whereSeparator: \.isWhitespace).map(String.init) where rawToken.contains("/") {
            let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`:;,()[]{}"))
            let components = token
                .split(separator: "/")
                .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\"'`:;,()[]{}")) }
                .filter { !$0.isEmpty }

            for component in components {
                if let known = knownTargets.first(where: { component.caseInsensitiveCompare($0) == .orderedSame }) {
                    return known
                }
            }

            if let cmakeIndex = components.firstIndex(of: "CMakeFiles"),
               components.indices.contains(components.index(after: cmakeIndex)) {
                let target = components[components.index(after: cmakeIndex)]
                    .replacingOccurrences(of: ".dir", with: "")
                if let cleaned = cleanedTargetName(target) {
                    return cleaned
                }
            }
        }

        return nil
    }

    private static func cleanedTargetName(_ rawValue: String) -> String? {
        let cleaned = rawValue
            .replacingOccurrences(of: ".dir", with: "")
            .replacingOccurrences(of: ".build", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .:/\\\"'`()[]{}"))
        guard !cleaned.isEmpty,
              !cleaned.hasSuffix(".o"),
              !cleaned.hasSuffix(".d"),
              !cleaned.hasSuffix(".swiftdeps"),
              !cleaned.hasSuffix(".swiftmodule") else { return nil }
        return cleaned
    }

    private static func firstRegexCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange])
    }

    private static func clipped(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit - 1)) + "…"
    }
}
