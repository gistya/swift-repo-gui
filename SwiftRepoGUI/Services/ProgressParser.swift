import Foundation

nonisolated struct BuildProgressSnapshot: Sendable, Equatable, Hashable {
    var completedSteps: Int
    var totalSteps: Int
    var fraction: Double
    var etaSeconds: Double?

    static let zero = BuildProgressSnapshot(completedSteps: 0, totalSteps: 0, fraction: 0, etaSeconds: nil)
}

enum ProgressParser {
    static func parse(line: String, startedAt: Date, previous: BuildProgressSnapshot) -> BuildProgressSnapshot {
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
                etaSeconds: eta
            )
        }

        if line.localizedCaseInsensitiveContains("Building") ||
            line.localizedCaseInsensitiveContains("Compiling") ||
            line.localizedCaseInsensitiveContains("Linking") {
            let bump = min(previous.fraction + 0.002, 0.95)
            return BuildProgressSnapshot(
                completedSteps: previous.completedSteps,
                totalSteps: previous.totalSteps,
                fraction: bump,
                etaSeconds: previous.etaSeconds
            )
        }

        return previous
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
}