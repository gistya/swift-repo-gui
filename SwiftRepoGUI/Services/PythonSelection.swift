import Foundation

/// A Python interpreter found on disk, identified by the directory that provides it.
nonisolated struct InstalledPython: Identifiable, Sendable, Equatable {
    /// The directory to put on `PATH`. It must contain an executable named exactly `python3` —
    /// that is the name the build scripts' `#!/usr/bin/env python3` shebang looks up, so a
    /// directory offering only `python` or `python3.13` cannot satisfy them.
    let binDirectory: String
    /// Full version as the interpreter reports it, e.g. "3.13.14".
    let version: String
    let major: Int
    let minor: Int
    let patch: Int

    var id: String { binDirectory }
    var executablePath: String { binDirectory + "/python3" }
    var featureVersion: String { "\(major).\(minor)" }
    var display: String { "Python \(version) — \(binDirectory)" }
}

/// Which Python the app's spawned build commands should use.
///
/// `build-script` and `update-checkout` both begin `#!/usr/bin/env python3`, so the interpreter is
/// decided purely by `PATH` order — there is no flag to pass. This front-loads the chosen
/// interpreter's directory on the CHILD PROCESS only, leaving the shell and the rest of the machine
/// alone.
nonisolated public struct PythonSelection: Sendable, Equatable {
    /// Directory containing the `python3` to use. Empty = automatic (see `automaticChoice`).
    var binDirectory: String = ""

    static let automatic = PythonSelection()
    static let defaultsKey = "buildPythonBinDirectory"

    /// The feature release automatic mode targets. Pinned rather than "newest installed" because a
    /// newly installed Python (3.14 here) otherwise silently takes over every build the moment it
    /// lands on PATH, which is exactly the churn this setting exists to stop.
    static let preferredMajor = 3
    static let preferredMinor = 13

    /// The persisted selection (what the Build Settings picker writes).
    public static func current(_ defaults: UserDefaults = .standard) -> PythonSelection {
        PythonSelection(binDirectory: defaults.string(forKey: defaultsKey) ?? "")
    }

    var trimmedBinDirectory: String? {
        let trimmed = binDirectory.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// What automatic mode picks: the newest patch of the preferred feature release, or nothing at
    /// all if it isn't installed. Deliberately does NOT fall back to some other version — silently
    /// building with an unintended interpreter is the failure mode being avoided.
    static func automaticChoice(among installed: [InstalledPython]) -> InstalledPython? {
        installed
            .filter { $0.major == preferredMajor && $0.minor == preferredMinor }
            .max { $0.patch < $1.patch }
    }

    /// The directory to front-load, or nil to leave `PATH` untouched.
    func resolvedBinDirectory(installed: [InstalledPython]) -> String? {
        guard let explicit = trimmedBinDirectory else {
            return Self.automaticChoice(among: installed)?.binDirectory
        }
        // Honour an explicit choice as long as it still provides python3 — including one discovery
        // never enumerated, such as a virtualenv. If it has gone away, change nothing rather than
        // quietly substituting a different interpreter.
        return FileManager.default.isExecutableFile(atPath: explicit + "/python3") ? explicit : nil
    }

    func apply(
        to environment: inout [String: String],
        installed: [InstalledPython] = InstalledPythons.discover()
    ) {
        guard let directory = resolvedBinDirectory(installed: installed) else { return }
        PathEnvironment.frontLoad([directory], in: &environment)
    }

    /// One-line description for the build log header / settings summary.
    func summary(installed: [InstalledPython]) -> String {
        guard let directory = resolvedBinDirectory(installed: installed) else {
            if trimmedBinDirectory != nil { return "selected interpreter is missing — using system default" }
            return "system default (Python \(Self.preferredMajor).\(Self.preferredMinor) not found)"
        }
        let known = installed.first { $0.binDirectory == directory }
        let version = known.map { "Python \($0.version)" } ?? "python3"
        let mode = trimmedBinDirectory == nil ? " (automatic)" : ""
        return "\(version)\(mode) — \(directory)"
    }
}

/// Locates the Python interpreters installed on this machine.
nonisolated enum InstalledPythons {
    /// Every usable `python3`, newest first, deduped so two doors into the same interpreter don't
    /// both appear.
    static func discover() -> [InstalledPython] {
        var found: [InstalledPython] = []
        var seenExecutables = Set<String>()

        for directory in candidateDirectories() {
            let executable = directory + "/python3"
            guard FileManager.default.isExecutableFile(atPath: executable) else { continue }
            // `/usr/local/bin/python3` is typically a symlink into a framework's bin directory;
            // resolving first means the same interpreter isn't offered twice under two paths.
            let resolved = URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
            guard seenExecutables.insert(resolved).inserted else { continue }
            guard let version = reportedVersion(of: executable) else { continue }
            found.append(InstalledPython(
                binDirectory: directory,
                version: version.full,
                major: version.major,
                minor: version.minor,
                patch: version.patch
            ))
        }

        return found.sorted {
            ($0.major, $0.minor, $0.patch) > ($1.major, $1.minor, $1.patch)
        }
    }

    /// Candidate directories, MOST SPECIFIC FIRST. Ordering matters because of the dedupe above:
    /// when a generic directory is just a symlink into a version-specific one, the version-specific
    /// path is the one offered, which stays correct even if the generic symlink is later repointed
    /// at a different release.
    private static func candidateDirectories() -> [String] {
        var directories: [String] = []
        // python.org framework installs.
        directories += subdirectories(of: "/Library/Frameworks/Python.framework/Versions").map { $0 + "/bin" }
        // Homebrew keg-only formulae (python@3.13, python@3.14, …).
        for opt in ["/opt/homebrew/opt", "/usr/local/opt"] {
            directories += subdirectories(of: opt, prefixedBy: "python@").map { $0 + "/bin" }
        }
        // pyenv.
        directories += subdirectories(of: NSHomeDirectory() + "/.pyenv/versions").map { $0 + "/bin" }
        // Generic locations last — these are usually symlinks into one of the above.
        directories += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        return directories
    }

    private static func subdirectories(of root: String, prefixedBy prefix: String = "") -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { return [] }
        return entries.sorted()
            .filter { prefix.isEmpty || $0.hasPrefix(prefix) }
            .map { root + "/" + $0 }
    }

    /// Ask the interpreter itself rather than inferring from its path — a directory name says
    /// nothing reliable about what it actually runs.
    static func reportedVersion(of executable: String) -> (full: String, major: Int, minor: Int, patch: Int)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8) else { return nil }
            return parseVersion(fromVersionOutput: output)
        } catch {
            return nil
        }
    }

    /// Parse `python3 --version` output: "Python 3.13.14".
    static func parseVersion(fromVersionOutput output: String) -> (full: String, major: Int, minor: Int, patch: Int)? {
        guard let match = output.firstMatch(of: /Python\s+(\d+)\.(\d+)(?:\.(\d+))?/),
              let major = Int(match.1), let minor = Int(match.2) else { return nil }
        let patch = match.3.flatMap { Int($0) } ?? 0
        return ("\(major).\(minor).\(patch)", major, minor, patch)
    }
}
