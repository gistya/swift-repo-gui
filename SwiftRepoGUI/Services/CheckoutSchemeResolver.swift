import Foundation

nonisolated enum CheckoutSchemeResolver {
    /// Reads the swift repo's current branch once (async, non-blocking) and resolves the scheme.
    static func resolve(
        swiftDirectory: URL,
        overrideScheme: String? = nil
    ) async -> (scheme: String, branch: String, source: SchemeResolutionSource) {
        let branch = await currentBranch(in: swiftDirectory)
        return resolve(swiftDirectory: swiftDirectory, currentBranch: branch, overrideScheme: overrideScheme)
    }

    /// Pure resolution given an already-read branch (no git spawn) — lets a caller read the branch
    /// once and share it with `availableSchemes(_:currentBranch:)`.
    static func resolve(
        swiftDirectory: URL,
        currentBranch branch: String?,
        overrideScheme: String? = nil
    ) -> (scheme: String, branch: String, source: SchemeResolutionSource) {
        if let override = overrideScheme?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return (override, branch ?? override, .manualOverride)
        }

        let configURL = swiftDirectory
            .appendingPathComponent("utils/update_checkout/update-checkout-config.json")

        guard let config = loadConfig(at: configURL) else {
            let fallback = branch ?? "main"
            return (fallback, fallback, .branchFallback)
        }

        let schemes = config.schemes
        guard let branch else {
            return (config.defaultScheme, config.defaultScheme, .defaultScheme)
        }

        if let match = schemes.first(where: { $0.name == branch }) {
            return (match.name, branch, .branchName)
        }

        if let match = schemes.first(where: { $0.aliases.contains(branch) }) {
            return (match.name, branch, .alias)
        }

        if let match = schemes.first(where: { $0.swiftBranch == branch }) {
            return (match.name, branch, .swiftRepoBranch)
        }

        return (branch, branch, .branchFallback)
    }

    static func availableSchemes(swiftDirectory: URL) async -> [String] {
        let branch = await currentBranch(in: swiftDirectory)
        return availableSchemes(swiftDirectory: swiftDirectory, currentBranch: branch)
    }

    static func availableSchemes(swiftDirectory: URL, currentBranch branch: String?) -> [String] {
        let configURL = swiftDirectory
            .appendingPathComponent("utils/update_checkout/update-checkout-config.json")
        var schemes = loadConfig(at: configURL)?.schemes.map(\.name) ?? []
        if let branch, !schemes.contains(branch) {
            schemes.append(branch)
        }
        if schemes.isEmpty { schemes.append("main") }
        return schemes.sorted()
    }

    static func currentBranch(in swiftDirectory: URL) async -> String? {
        if let branch = await gitOutput(["rev-parse", "--abbrev-ref", "HEAD"], in: swiftDirectory),
           branch != "HEAD" {
            return branch
        }
        return await branchPointingAtHead(in: swiftDirectory)
    }

    private static func branchPointingAtHead(in swiftDirectory: URL) async -> String? {
        guard let refs = await gitOutput(
            ["for-each-ref", "--points-at", "HEAD", "--format=%(refname)", "refs/heads", "refs/remotes"],
            in: swiftDirectory
        ) else {
            return nil
        }

        let refNames = refs
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        let localBranches = refNames.compactMap { ref -> String? in
            guard ref.hasPrefix("refs/heads/") else { return nil }
            return String(ref.dropFirst("refs/heads/".count))
        }
        if let branch = preferredBranchName(localBranches) {
            return branch
        }

        let remoteBranches = refNames.compactMap(remoteBranchName)
        return preferredBranchName(remoteBranches)
    }

    private static func remoteBranchName(from ref: String) -> String? {
        guard ref.hasPrefix("refs/remotes/") else { return nil }
        let remoteRef = String(ref.dropFirst("refs/remotes/".count))
        guard !remoteRef.hasSuffix("/HEAD") else { return nil }
        guard let slash = remoteRef.firstIndex(of: "/") else { return nil }
        return String(remoteRef[remoteRef.index(after: slash)...])
    }

    private static func preferredBranchName(_ names: [String]) -> String? {
        names
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                let lhsRank = branchPreferenceRank(lhs)
                let rhsRank = branchPreferenceRank(rhs)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            .first
    }

    private static func branchPreferenceRank(_ name: String) -> Int {
        if name.hasPrefix("release/") || name.hasPrefix("swift/release/") { return 0 }
        if name == "main" || name == "master" { return 2 }
        return 1
    }

    private static func gitOutput(_ arguments: [String], in directory: URL) async -> String? {
        await AsyncProcess.gitOutput(["-C", directory.path] + arguments)
    }

    private static func loadConfig(at url: URL) -> ParsedCheckoutConfig? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let branchSchemes = json["branch-schemes"] as? [String: Any] else {
            return nil
        }

        let defaultScheme = json["default-branch-scheme"] as? String ?? "main"
        let schemes: [ParsedScheme] = branchSchemes.compactMap { name, value in
            guard let scheme = value as? [String: Any] else { return nil }
            let aliases = scheme["aliases"] as? [String] ?? []
            let repos = scheme["repos"] as? [String: String] ?? [:]
            let swiftBranch = repos["swift"] ?? name
            return ParsedScheme(name: name, aliases: aliases, swiftBranch: swiftBranch)
        }

        return ParsedCheckoutConfig(defaultScheme: defaultScheme, schemes: schemes)
    }
}

nonisolated enum SchemeResolutionSource: String, Sendable, Equatable, Hashable {
    case manualOverride
    case branchName
    case alias
    case swiftRepoBranch
    case defaultScheme
    case branchFallback

    var explanation: String {
        switch self {
        case .manualOverride:
            "Using your manually selected checkout scheme."
        case .branchName:
            "Matched the current swift branch name to a checkout scheme."
        case .alias:
            "Matched the current swift branch to a scheme alias."
        case .swiftRepoBranch:
            "Matched a scheme whose swift repo branch equals your current branch."
        case .defaultScheme:
            "Could not read the current swift branch; using the default scheme from update-checkout-config.json."
        case .branchFallback:
            "No configured scheme matched the current swift branch; using the branch name as the update-checkout scheme."
        }
    }
}

private struct ParsedCheckoutConfig {
    let defaultScheme: String
    let schemes: [ParsedScheme]
}

private struct ParsedScheme {
    let name: String
    let aliases: [String]
    let swiftBranch: String
}
