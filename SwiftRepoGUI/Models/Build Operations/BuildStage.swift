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

        return context.progress.stage
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

    /// The stage a job begins in, before any phase banner is seen.
    ///
    /// Raw `ninja` invocations only ever compile — ninja never runs tests or installs — so they
    /// stay `.building` for their whole lifetime. `update-checkout` is a source sync, so it reads
    /// as `.deploying` (the closest non-compile phase). Full `build-script` / toolchain runs start
    /// building and are advanced by the banners they emit (`detect(bannerIn:)`).
    static func baseStage(for kind: BuildOperationKind) -> BuildStage {
        switch kind {
        case .updateDependencies:
            return .deploying
        case .incrementalFrontend, .incrementalSwiftRepo, .incrementalEverything,
             .dependencyBuild, .updateAndRebuild, .buildScript, .freshBuild, .buildToolchain:
            return .building
        }
    }

    /// Detects a stage change from a single line of build output — but ONLY from the authoritative,
    /// line-anchored phase banners that `build-script`, `build-script-impl`, and the Python product
    /// pipeline print. Everything else (compiler commands, `[x/y]` ninja lines, warnings) returns
    /// `nil`, meaning "keep the current stage". This is deliberately NOT a substring search: a
    /// filename or path that merely contains "test"/"install"/"benchmark" must not move the stage.
    static func detect(bannerIn rawLine: String) -> BuildStage? {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        let lower = line.lowercased()

        // Distinctive full-line status prints (anchored at line start; a compiler command never
        // begins with these sentences).
        if lower.hasPrefix("running swift benchmarks for") { return .measuring }
        if lower.hasPrefix("running swift tests for") { return .testing }
        if lower.hasPrefix("building the standard library for") { return .building }

        // Phase banners have the exact shape `--- <phase> ---`.
        guard line.hasPrefix("--- "), line.hasSuffix(" ---") else { return nil }
        let phase = line.dropFirst(4).dropLast(4).trimmingCharacters(in: .whitespaces).lowercased()
        guard !phase.isEmpty else { return nil }

        if phase.hasPrefix("installing")
            || phase.contains("installable package")
            || phase.hasPrefix("extracting symbols") {
            return .deploying
        }
        if phase.contains("benchmark") {
            return .measuring
        }
        if phase.hasPrefix("running tests for")
            || phase.hasPrefix("running lldb")
            || phase.hasPrefix("check-") {
            return .testing
        }
        // A product finished testing, or a new product's clean/build began → back to building.
        if phase.hasPrefix("finished tests for")
            || phase.hasPrefix("building")
            || phase.hasPrefix("cleaning") {
            return .building
        }
        // Unknown banner (e.g. "Bootstrap Local CMake") — don't touch the stage.
        return nil
    }

    static func moduleDisplay(for context: BuildOperationsContext) -> String {
        moduleDisplay(for: stage(for: context), context: context)
    }

    static func moduleDisplay(for stage: BuildStage, context: BuildOperationsContext) -> String {
        if stage == .failed { return String(localized: "ERROR") }
        guard stage.isActive else { return String(localized: "READY") }
        // The last confident target/phase parsed off the output stream (sticky — junk lines don't
        // clobber it). Falls back to the repo/operation name only until the first real target lands.
        if let label = context.progress.moduleLabel, !label.isEmpty {
            return clipped(label, limit: 22)
        }
        if let target = context.activeJob?.targetRepository, !target.isEmpty {
            return clipped(target, limit: 22)
        }
        return clipped(context.activeJob?.kind.title ?? String(localized: "RUNNING"), limit: 22)
    }

    /// The LCD label for a single output line, or `nil` when the line names no target/phase (so the
    /// caller keeps the previous label). Recognizes phase banners (`--- Installing swift ---` →
    /// "swift", `--- Extracting symbols ---`) and structured compile lines; rejects noise.
    static func moduleLabel(for line: String) -> String? {
        if let banner = bannerModuleLabel(for: line) { return banner }
        return primaryTarget(from: line)
    }

    private static func bannerModuleLabel(for rawLine: String) -> String? {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("--- "), line.hasSuffix(" ---") else { return nil }
        let phase = line.dropFirst(4).dropLast(4).trimmingCharacters(in: .whitespaces)
        let lower = phase.lowercased()

        if lower.hasPrefix("extracting symbols") { return "Extracting symbols" }
        if lower.contains("installable package") { return "Installable package" }
        if lower.hasPrefix("running lldb") { return "lldb" }
        if lower.hasPrefix("check-") { return String(phase.split(separator: " ").first ?? "") }
        // "<verb> [tests for] <product>" → the product name. Longer prefixes first.
        for prefix in ["building tests for ", "finished tests for ", "running tests for ",
                       "installing ", "cleaning ", "building "] where lower.hasPrefix(prefix) {
            let target = String(phase.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !target.isEmpty { return target }
        }
        return nil
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

        // Verb-anchored fallback: the target is the first identifier-like token that FOLLOWS a known
        // build verb ("Testing SwiftParseTests" → "SwiftParseTests"). Anchoring on a verb is what
        // stops junk lines — `ld: warning …`, `-- Installing: /path`, `… && ninja` — from yielding
        // "ld"/"--"/"&&": those have no leading verb, or the token after it fails `qualifiedTarget`.
        let tokens = text
            .replacingOccurrences(of: ":", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        var sawVerb = false
        for token in tokens {
            let lower = token.trimmingCharacters(in: .punctuationCharacters).lowercased()
            if targetVerbs.contains(lower) {
                sawVerb = true
                continue
            }
            guard sawVerb, let qualified = qualifiedTarget(token) else { continue }
            return qualified
        }

        return nil
    }

    /// Build verbs that a real "compiling this target" description starts with. A line without one is
    /// treated as non-structured output and yields no label.
    private static let targetVerbs: Set<String> = [
        "building", "compiling", "linking", "testing", "installing", "cleaning", "generating"
    ]

    /// Noise words that are never a target even though they read like identifiers.
    private static let targetNoise: Set<String> = [
        "c", "cxx", "cpp", "swift", "swiftc", "clang", "gcc", "ld", "cc", "ar", "ranlib",
        "object", "objects", "module", "modules", "library", "libraries", "executable",
        "static", "shared", "archive", "tablegen", "target", "source", "sources",
        "the", "for", "and", "with", "into", "from", "of", "in", "on", "to", "at", "by",
        "warning", "error", "note", "ignoring", "duplicate", "skipping", "using"
    ]

    /// A token that plausibly IS a target name: identifier-shaped, not noise, no path/flag/glue chars.
    private static func qualifiedTarget(_ token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`:;,()[]{}"))
        guard trimmed.count >= 3,
              !trimmed.contains("."), !trimmed.contains("/"), !trimmed.contains("="),
              trimmed.range(of: "^[A-Za-z][A-Za-z0-9_+-]*$", options: .regularExpression) != nil,
              !targetNoise.contains(trimmed.lowercased()) else { return nil }
        return trimmed
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
