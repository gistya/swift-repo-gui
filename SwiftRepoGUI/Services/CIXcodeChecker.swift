import Foundation

/// Which ci.swift.org machine pool to compare against.
///
/// The two pools genuinely differ — as of 2026-07 the arm64 nodes are labelled `Xcode26` while the
/// x86_64 pull request machines are on `Xcode-16.2` — so "what Xcode does CI use" has no single
/// answer and the user picks which fleet is relevant to them.
nonisolated enum CIFleet: String, CaseIterable, Identifiable, Sendable {
    case appleSilicon = "arm64"
    case intel = "x86_64"

    var id: String { rawValue }
    var arch: String { rawValue }
    var display: String {
        switch self {
        case .appleSilicon: "Apple Silicon (arm64)"
        case .intel: "Intel (x86_64)"
        }
    }

    /// The pool matching this machine — the sensible default, since it's the one a local build maps to.
    static var local: CIFleet {
        #if arch(arm64)
        .appleSilicon
        #else
        .intel
        #endif
    }

    static let defaultsKey = "ciXcodeFleet"

    /// The persisted choice, falling back to this machine's own architecture.
    static func current(_ defaults: UserDefaults = .standard) -> CIFleet {
        defaults.string(forKey: defaultsKey).flatMap(CIFleet.init(rawValue:)) ?? .local
    }
}

/// A parsed Xcode version — from a ci.swift.org node label (`Xcode26`, `Xcode-26.3`, `Xcode15.2b`),
/// from the CI dashboard ("Xcode 16.2"), or from local `xcodebuild -version` ("26.3"). Node labels
/// are often major-only, so `minor` is optional and comparisons use the available precision.
nonisolated struct XcodeVersion: Hashable, Sendable {
    let major: Int
    let minor: Int?
    let isBeta: Bool

    init(major: Int, minor: Int?, isBeta: Bool = false) {
        self.major = major
        self.minor = minor
        self.isBeta = isBeta
    }

    /// Parse a version string like `26.3` or `16.2`.
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

    /// Does this local version match CI's, at the precision CI provides? A major-only CI label
    /// (`Xcode26`) matches any minor of that major; a `26.3` label needs an exact minor. Beta is
    /// ignored (CI's beta labels are for legacy lanes, not the mainline compare).
    func matchesCILabel(_ ci: XcodeVersion) -> Bool {
        guard major == ci.major else { return false }
        if let ciMinor = ci.minor { return minor == ciMinor }
        return true
    }
}

/// The result of comparing the locally selected Xcode against a ci.swift.org fleet.
nonisolated struct CIXcodeStatus: Equatable, Sendable {
    /// Local `xcodebuild -version`, e.g. "26.3".
    let localVersion: String
    /// Local build number, e.g. "17C529" (nil if it couldn't be read).
    let localBuild: String?
    /// The fleet this comparison was made against.
    let fleet: CIFleet
    /// The most common Xcode among the online nodes of that fleet, for display.
    let primaryCIVersion: String
    /// Every distinct Xcode among those nodes, newest first.
    let ciVersions: [String]
    /// Whether the local Xcode matches the fleet's primary (at the label's precision).
    let matches: Bool
    /// True when the label had no minor, so the comparison could only be done at major precision.
    let comparedAtMajorOnly: Bool
    /// The Xcode stated in the ci.swift.org front-page "Node information" blurb, e.g. "16.2". This is
    /// the project's own published recommendation, and can differ from what a given fleet's machines
    /// actually carry — shown alongside so the discrepancy is visible rather than confusing.
    let publishedVersion: String?
    /// The host macOS version from that same blurb, e.g. "15.1.1".
    let publishedHostOS: String?

    /// True when the published blurb disagrees with the selected fleet's machines.
    var publishedDiffersFromFleet: Bool {
        guard let publishedVersion,
              let published = XcodeVersion(parsingVersionString: publishedVersion) else { return false }
        return published.display != primaryCIVersion
    }
}

/// The inputs a check's result depends on. Bundled so a change to EITHER invalidates a cached
/// verdict — a result computed for a different Xcode or a different fleet is stale, not reusable.
nonisolated struct CIXcodeCheckInputs: Equatable, Sendable {
    var toolchain: ToolchainSelection
    var fleet: CIFleet
}

/// Lifecycle of the ci.swift.org parity check. A failed check is a distinct, RECOVERABLE state —
/// modelling it as "no status" would hide the banner, and with it the only way to retry.
nonisolated enum CIXcodeCheckState: Equatable, Sendable {
    case idle
    case checking
    case failed
    case loaded(CIXcodeStatus)

    var status: CIXcodeStatus? {
        guard case .loaded(let status) = self else { return nil }
        return status
    }

    /// Should an automatic (`onAppear`) check start?
    ///
    /// Yes when nothing has run yet, or when the inputs changed since the last check — a verdict
    /// about a previously selected Xcode or fleet is worse than none. Deliberately NO for `.failed`
    /// at unchanged inputs: retry is the Recheck button's job, so revisiting the tab can't re-run a
    /// network timeout each time.
    func shouldAutoCheck(checked: CIXcodeCheckInputs?, current: CIXcodeCheckInputs) -> Bool {
        self == .idle || checked != current
    }
}

/// Checks what Xcode the ci.swift.org build nodes are running and compares it against the Xcode this
/// app is set to build with. Everything is best-effort: any network, decode, or tooling failure
/// returns `nil` and the UI shows a retryable failure row.
///
/// TWO SOURCES, deliberately. Node *labels* (`/computer/api/json`) say what a given machine carries
/// and are per-fleet — the arm64 and x86_64 pools disagree, which is why the fleet is selectable.
/// The front-page "Node information" blurb (`primaryView.description`) is the Swift project's own
/// published statement. Neither subsumes the other, so both are reported.
nonisolated enum CIXcodeChecker {
    /// Node labels carry the Xcode version. The endpoint is trimmed to only the fields we read.
    private static let nodesURL = URL(string:
        "https://ci.swift.org/computer/api/json?tree=computer[displayName,offline,temporarilyOffline,assignedLabels[name]]"
    )!

    /// The front-page description, as a small JSON payload instead of the ~1.6 MB rendered page.
    /// NOTE: it lives on the PRIMARY VIEW — the root `?tree=description` is null.
    private static let dashboardURL = URL(string:
        "https://ci.swift.org/api/json?tree=primaryView%5Bdescription%5D"
    )!

    static func check(
        toolchain: ToolchainSelection = .current(),
        fleet: CIFleet = .current()
    ) async -> CIXcodeStatus? {
        async let localOut = runXcodebuildVersion(toolchain: toolchain)
        async let nodes = fetchNodes()
        async let description = fetchDashboardDescription()

        guard let out = await localOut,
              let local = parseLocalXcode(fromXcodebuildOutput: out),
              let localVersion = XcodeVersion(parsingVersionString: local.version) else { return nil }
        guard let nodes = await nodes else { return nil }

        // Count Xcode labels across the online nodes of the chosen fleet (dedup per node first, since
        // a node advertises the same version in several composite labels).
        var counts: [XcodeVersion: Int] = [:]
        for node in nodes where isOnline(node) && nodeArch(node) == fleet.arch {
            let labels = (node.assignedLabels ?? []).compactMap(\.name)
            for version in Set(labels.compactMap(parseXcodeVersion(fromLabel:))) {
                counts[version, default: 0] += 1
            }
        }
        guard let primary = counts.max(by: { $0.value < $1.value })?.key else { return nil }

        let distinct = counts.keys.sorted {
            ($0.major, $0.minor ?? -1) > ($1.major, $1.minor ?? -1)
        }
        let published = await description.flatMap(parseCIXcode(fromDashboardDescription:))
        return CIXcodeStatus(
            localVersion: local.version,
            localBuild: local.build,
            fleet: fleet,
            primaryCIVersion: primary.display,
            ciVersions: distinct.map(\.display),
            matches: localVersion.matchesCILabel(primary),
            comparedAtMajorOnly: primary.minor == nil,
            publishedVersion: published?.xcode,
            publishedHostOS: published?.hostOS
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

    /// Pull the Xcode (and host macOS) version out of the dashboard's "Node information" block.
    ///
    /// Two traps this deliberately avoids: the description carries a commented-out banner that
    /// mentions Xcode, and an icon URL (`xcode-64x64_2x.png`) that a loose pattern happily reads as
    /// "Xcode 64". So HTML comments are stripped first, and the version must be separated from the
    /// word "Xcode" by whitespace.
    static func parseCIXcode(fromDashboardDescription html: String) -> (xcode: String, hostOS: String?)? {
        let live = html.replacing(/<!--.*?-->/.dotMatchesNewlines(), with: " ")
        // Anchor to the node-information section when present, so unrelated Xcode mentions elsewhere
        // in the blurb can't win.
        let section: Substring
        if let heading = live.firstRange(of: "Node information") {
            section = live[heading.upperBound...]
        } else {
            section = live[...]
        }
        guard let xcode = section.firstMatch(of: /[Xx]code\s+(\d+(?:\.\d+)*)/) else { return nil }
        let hostOS = section.firstMatch(of: /Host OS:\s*macOS\s+([\d.]+)/).map { String($0.1) }
        return (String(xcode.1), hostOS)
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
    nonisolated private struct NodesResponse: Decodable { let computer: [APINode] }
    nonisolated private struct DashboardResponse: Decodable {
        struct View: Decodable { let description: String? }
        let primaryView: View?
    }

    private static func fetchNodes(timeout: TimeInterval = 12) async -> [APINode]? {
        await fetch(nodesURL, timeout: timeout, as: NodesResponse.self)?.computer
    }

    private static func fetchDashboardDescription(timeout: TimeInterval = 12) async -> String? {
        await fetch(dashboardURL, timeout: timeout, as: DashboardResponse.self)?.primaryView?.description
    }

    private static func fetch<T: Decodable>(_ url: URL, timeout: TimeInterval, as: T.Type) async -> T? {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("SwiftBuilder (Xcode-parity check)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    /// Run `/usr/bin/xcodebuild -version` on a background dispatch queue, so the brief blocking wait
    /// never touches the main actor or a cooperative thread. This is a one-shot check, so a single
    /// background thread parked for ~a second is fine.
    private static func runXcodebuildVersion(toolchain: ToolchainSelection) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
                process.arguments = ["-version"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                // Report the Xcode the app will BUILD with (the in-app selection), not whatever the
                // shell that launched us points at. `/usr/bin/xcodebuild` honours DEVELOPER_DIR.
                var environment = ProcessInfo.processInfo.environment
                toolchain.apply(to: &environment)
                process.environment = environment
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
