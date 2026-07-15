import Foundation

/// A parsed Xcode version — from a ci.swift.org node label (`Xcode26`, `Xcode-26.3`, `Xcode15.2b`)
/// or from local `xcodebuild -version` (`26.3`). Node labels are often major-only, so `minor` is
/// optional and comparisons are done at the available precision.
nonisolated struct XcodeVersion: Hashable, Sendable {
    let major: Int
    let minor: Int?
    let isBeta: Bool

    init(major: Int, minor: Int?, isBeta: Bool = false) {
        self.major = major
        self.minor = minor
        self.isBeta = isBeta
    }

    /// Parse a local version string like `26.3` (from `xcodebuild -version`).
    init?(parsingVersionString string: String) {
        let parts = string.split(separator: ".")
        guard let major = parts.first.flatMap({ Int($0) }) else { return nil }
        self.major = major
        self.minor = parts.count > 1 ? Int(parts[1]) : nil
        self.isBeta = false
    }

    var display: String {
        var s = "Xcode \(major)"
        if let minor { s += ".\(minor)" }
        if isBeta { s += " beta" }
        return s
    }

    /// Does this local version match a CI node's version, at the precision the CI label provides?
    /// A major-only CI label (`Xcode26`) matches any minor of that major; a `26.3` label needs an
    /// exact minor. Beta is ignored (CI's beta labels are for legacy lanes, not the mainline compare).
    func matchesCILabel(_ ci: XcodeVersion) -> Bool {
        guard major == ci.major else { return false }
        if let ciMinor = ci.minor { return minor == ciMinor }
        return true
    }
}

/// The result of comparing the locally selected Xcode against the ci.swift.org build fleet.
nonisolated struct CIXcodeStatus: Equatable, Sendable {
    /// Local `xcodebuild -version`, e.g. "26.3".
    let localVersion: String
    /// Local build number, e.g. "17C529" (nil if it couldn't be read).
    let localBuild: String?
    /// The architecture the comparison used ("arm64" / "x86_64"), matched to this machine.
    let arch: String
    /// The most common Xcode among the online CI nodes of this architecture, for display.
    let primaryCIVersion: String
    /// Every distinct Xcode among the online CI nodes of this architecture, newest first.
    let ciVersions: [String]
    /// Whether the local Xcode matches the CI primary (at the CI label's precision).
    let matches: Bool
    /// True when the CI label had no minor, so the comparison could only be done at major precision.
    let comparedAtMajorOnly: Bool
}

/// Checks what Xcode the ci.swift.org build nodes are running (via the public Jenkins API) and
/// compares it against the Xcode selected on this machine. Everything is best-effort: any network,
/// decode, or tooling failure returns `nil` and the UI simply shows nothing.
nonisolated enum CIXcodeChecker {
    // The machine's own architecture — the CI nodes we compare against are the ones of the same arch,
    // since that's what a local build here would map to.
    #if arch(arm64)
    static let localArch = "arm64"
    #elseif arch(x86_64)
    static let localArch = "x86_64"
    #else
    static let localArch = "unknown"
    #endif

    /// Node labels carry the Xcode version. The endpoint is trimmed to only the fields we read.
    private static let apiURL = URL(string:
        "https://ci.swift.org/computer/api/json?tree=computer[displayName,offline,temporarilyOffline,assignedLabels[name]]"
    )!

    static func check() async -> CIXcodeStatus? {
        async let localOut = runXcodebuildVersion()
        async let nodes = fetchNodes()

        guard let out = await localOut,
              let local = parseLocalXcode(fromXcodebuildOutput: out),
              let localVersion = XcodeVersion(parsingVersionString: local.version) else { return nil }
        guard let nodes = await nodes else { return nil }

        // Count Xcode labels across the online nodes of our architecture (dedup per node first, since a
        // node advertises the same version in several composite labels).
        var counts: [XcodeVersion: Int] = [:]
        for node in nodes where isOnline(node) && nodeArch(node) == localArch {
            let labels = (node.assignedLabels ?? []).compactMap(\.name)
            for version in Set(labels.compactMap(parseXcodeVersion(fromLabel:))) {
                counts[version, default: 0] += 1
            }
        }
        guard let primary = counts.max(by: { $0.value < $1.value })?.key else { return nil }

        let distinct = counts.keys.sorted {
            ($0.major, $0.minor ?? -1) > ($1.major, $1.minor ?? -1)
        }
        return CIXcodeStatus(
            localVersion: local.version,
            localBuild: local.build,
            arch: localArch,
            primaryCIVersion: primary.display,
            ciVersions: distinct.map(\.display),
            matches: localVersion.matchesCILabel(primary),
            comparedAtMajorOnly: primary.minor == nil
        )
    }

    // MARK: - Parsing (pure, unit-tested)

    /// Extract an Xcode version from a Jenkins label: `Xcode26`, `Xcode-26.3`, `Xcode15.2b`, or a
    /// composite like `macos-x86_64_Xcode-26.3`. Returns nil for labels with no Xcode token.
    static func parseXcodeVersion(fromLabel label: String) -> XcodeVersion? {
        guard let match = label.firstMatch(of: /[Xx]code-?(\d+)(?:\.(\d+))?(b\d*)?/),
              let major = Int(match.1) else { return nil }
        return XcodeVersion(major: major, minor: match.2.flatMap { Int($0) }, isBeta: match.3 != nil)
    }

    /// Parse `xcodebuild -version` output: "Xcode 26.3\nBuild version 17C529".
    static func parseLocalXcode(fromXcodebuildOutput output: String) -> (version: String, build: String?)? {
        guard let versionMatch = output.firstMatch(of: /Xcode\s+([\d.]+)/) else { return nil }
        let build = output.firstMatch(of: /Build version\s+(\S+)/).map { String($0.1) }
        return (String(versionMatch.1), build)
    }

    /// Derive a node's architecture from its display name / labels (`macos-node-arm64-i-…`,
    /// `macos-x86_64_Xcode-26.3`).
    static func nodeArch(_ node: APINode) -> String {
        let haystack = (
            (node.displayName ?? "") + " " + (node.assignedLabels ?? []).compactMap(\.name).joined(separator: " ")
        ).lowercased()
        if haystack.contains("arm64") { return "arm64" }
        if haystack.contains("x86_64") { return "x86_64" }
        return "unknown"
    }

    static func isOnline(_ node: APINode) -> Bool {
        node.offline == false && node.temporarilyOffline != true
    }

    // MARK: - I/O

    nonisolated struct APINode: Decodable, Sendable {
        let displayName: String?
        let offline: Bool?
        let temporarilyOffline: Bool?
        let assignedLabels: [APILabel]?
    }
    nonisolated struct APILabel: Decodable, Sendable { let name: String? }
    nonisolated private struct APIResponse: Decodable { let computer: [APINode] }

    private static func fetchNodes(timeout: TimeInterval = 12) async -> [APINode]? {
        var request = URLRequest(url: apiURL, timeoutInterval: timeout)
        request.setValue("SwiftBuilder (Xcode-parity check)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(APIResponse.self, from: data).computer
        } catch {
            return nil
        }
    }

    /// Run `/usr/bin/xcodebuild -version` (which respects `xcode-select`) on a background dispatch
    /// queue, so the brief blocking wait never touches the main actor or a cooperative thread. This is
    /// a one-shot launch check, so a single background thread parked for ~a second is fine.
    private static func runXcodebuildVersion() async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
                process.arguments = ["-version"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
