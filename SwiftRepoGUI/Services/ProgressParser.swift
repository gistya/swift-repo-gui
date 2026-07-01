import Foundation

nonisolated struct BuildProgressSnapshot: Sendable, Equatable, Hashable {
    var completedSteps: Int
    var totalSteps: Int
    var fraction: Double
    var etaSeconds: Double?
    var message: String?

    static let zero = BuildProgressSnapshot(completedSteps: 0, totalSteps: 0, fraction: 0, etaSeconds: nil, message: nil)
}

nonisolated enum ProgressParser {
    static func parse(line: String, startedAt: Date, previous: BuildProgressSnapshot) -> BuildProgressSnapshot {
        let message = displayMessage(from: line)

        if isConfigureActivity(line) {
            return indeterminate(message: message)
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
                message: message
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
                message: message
            )
        }

        guard let message else { return previous }
        if previous.totalSteps > 0, previous.completedSteps >= previous.totalSteps {
            return indeterminate(message: message)
        }

        var next = previous
        next.message = message
        return next
    }

    private static func indeterminate(message: String?) -> BuildProgressSnapshot {
        BuildProgressSnapshot(
            completedSteps: 0,
            totalSteps: 0,
            fraction: 0,
            etaSeconds: nil,
            message: message
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
