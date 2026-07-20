import Foundation

/// Shared helper for composing a child process's `PATH`.
nonisolated enum PathEnvironment {
    /// Front-load `directories` onto the `PATH` in `environment`.
    ///
    /// Order among `directories` is preserved (earlier wins), duplicates are dropped keeping the
    /// FIRST occurrence, and the existing path follows unchanged. Front-loading rather than
    /// replacing matters: a build still needs the user's ordinary tools, we only want the chosen
    /// ones to be found first.
    static func frontLoad(_ directories: [String], in environment: inout [String: String]) {
        guard !directories.isEmpty else { return }
        let existing = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        environment["PATH"] = (directories + existing)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
    }
}
