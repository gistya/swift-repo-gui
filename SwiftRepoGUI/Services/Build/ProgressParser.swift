import CompositionalInit
import Foundation

nonisolated public enum ProgressParser {
    public static func parse(line: String, startedAt: Date, previous: BuildProgressSnapshot) -> BuildProgressSnapshot {
        let message = displayMessage(from: line)
        // The stage only advances on an authoritative phase banner; otherwise it stays put.
        let stage = BuildStage.detect(bannerIn: line) ?? previous.stage
        // Likewise the LCD label is sticky: a line without a confident target keeps the last one.
        let moduleLabel = BuildStage.moduleLabel(for: line) ?? previous.moduleLabel

        if isConfigureActivity(line) {
            return indeterminate(message: message, stage: stage, moduleLabel: moduleLabel)
        }

        if let match = ninjaProgress(in: line) {
            let fraction = match.total > 0 ? Double(match.completed) / Double(match.total) : 0
            let elapsed = Date().timeIntervalSince(startedAt)
            let eta: Double?
            if match.completed > 0, fraction > 0, fraction < 1 {
                eta = elapsed * (1 - fraction) / fraction
            } else {
                eta = nil
            }
            return BuildProgressSnapshot(
                completedSteps: match.completed,
                totalSteps: match.total,
                fraction: fraction,
                etaSeconds: eta,
                message: message,
                stage: stage,
                moduleLabel: moduleLabel
            )
        }

        if line.localizedCaseInsensitiveContains("Building") ||
            line.localizedCaseInsensitiveContains("Compiling") ||
            line.localizedCaseInsensitiveContains("Linking") {
            return BuildProgressSnapshot(
                completedSteps: previous.completedSteps,
                totalSteps: previous.totalSteps,
                fraction: previous.fraction,
                etaSeconds: previous.etaSeconds,
                message: message,
                stage: stage,
                moduleLabel: moduleLabel
            )
        }

        guard let message else {
            guard stage != previous.stage || moduleLabel != previous.moduleLabel else { return previous }
            var next = previous
            next.stage = stage
            next.moduleLabel = moduleLabel
            return next
        }
        if previous.totalSteps > 0, previous.completedSteps >= previous.totalSteps {
            return indeterminate(message: message, stage: stage, moduleLabel: moduleLabel)
        }

        var next = previous
        next.message = message
        next.stage = stage
        next.moduleLabel = moduleLabel
        return next
    }

    private static func indeterminate(message: String?, stage: BuildStage, moduleLabel: String?) -> BuildProgressSnapshot {
        BuildProgressSnapshot(
            completedSteps: 0,
            totalSteps: 0,
            fraction: 0,
            etaSeconds: nil,
            message: message,
            stage: stage,
            moduleLabel: moduleLabel
        )
    }

    private static func ninjaProgress(in line: String) -> (completed: Int, total: Int)? {
        let patterns = [
            #"\[\s*(\d+)\s*/\s*(\d+)\s*\]"#,
            #"(\d+)\s*/\s*(\d+)\s+actions"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  match.numberOfRanges == 3,
                  let completedRange = Range(match.range(at: 1), in: line),
                  let totalRange = Range(match.range(at: 2), in: line),
                  let completed = Int(line[completedRange]),
                  let total = Int(line[totalRange]),
                  total > 0 else { continue }
            return (completed, total)
        }
        return nil
    }

    private static func displayMessage(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= 240 { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 240)
        return String(trimmed[..<end])
    }

    private static func isConfigureActivity(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        return lowercased.contains("re-running cmake") ||
            lowercased.hasPrefix("-- performing test") ||
            lowercased.hasPrefix("-- looking for") ||
            lowercased.hasPrefix("-- checking") ||
            lowercased.hasPrefix("-- detecting") ||
            lowercased.hasPrefix("-- configuring") ||
            lowercased.hasPrefix("-- generating") ||
            lowercased.hasPrefix("cmake warning") ||
            lowercased.hasPrefix("cmake error")
    }
}
