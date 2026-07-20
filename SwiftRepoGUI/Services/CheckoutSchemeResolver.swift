import Foundation

nonisolated public enum CheckoutSchemeResolver {
    /// Reads the swift repo's current branch once (async, non-blocking) and resolves the scheme.
    public static func resolve(
        swiftDirectory: URL,
        overrideScheme: String? = nil
    ) async -> (scheme: String, branch: String, source: SchemeResolutionSource) {
        let branch = await currentBranch(in: swiftDirectory)
        return resolve(swiftDirectory: swiftDirectory, currentBranch: branch, overrideScheme: overrideScheme)
    }

    /// Pure resolution given an already-read branch (no git spawn) — lets a caller read the branch
    /// once and share it with `availableSchemes(_:currentBranch:)`.
    public static func resolve(
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

        // The branch is not a scheme name, an alias, or any scheme's swift-repo branch — i.e. a custom
        // feature/fork branch (e.g. a compiler-work branch). Passing the raw branch name as `--scheme`
        // makes update-checkout fail with "'NoneType' object is not iterable", because no scheme by that
        // name exists in update-checkout-config.json. Fall back to the config's default scheme (typically
        // `main`) — what you'd choose by hand — and let --match-timestamp pin the siblings to that
        // scheme's branch at the swift HEAD's commit date. The manual override picker covers anything else.
        return (config.defaultScheme, branch, .defaultScheme)
    }

    public static func availableSchemes(swiftDirectory: URL) async -> [String] {
        let branch = await currentBranch(in: swiftDirectory)
        return availableSchemes(swiftDirectory: swiftDirectory, currentBranch: branch)
    }

    public static func availableSchemes(swiftDirectory: URL, currentBranch branch: String?) -> [String] {
        // Only real schemes from update-checkout-config.json — NOT the current branch name. A custom
        // branch (e.g. a compiler-fork branch) is not a scheme, so offering it as one lets the user pick
        // a value that makes update-checkout fail. Auto mode (no scheme) covers those branches.
        _ = branch
        let configURL = swiftDirectory
            .appendingPathComponent("utils/update_checkout/update-checkout-config.json")
        let schemes = loadConfig(at: configURL)?.schemes.map(\.name) ?? []
        return (schemes.isEmpty ? ["main"] : schemes).sorted()
    }

    public static func currentBranch(in swiftDirectory: URL) async -> String? {
        // Prefer reading `.git/HEAD` directly: a plain in-process file read works with the file
        // access the app already has (user-picked repo / granted paths), whereas a spawned `git`
        // subprocess does NOT reliably inherit that access under the App Sandbox, so `git rev-parse`
        // there returns nothing and the scheme falls back to the default. Git is only a fallback for
        // detached HEAD / worktree edge cases.
        if let branch = branchFromGitHead(in: swiftDirectory) {
            return branch
        }
        if let branch = await gitOutput(["rev-parse", "--abbrev-ref", "HEAD"], in: swiftDirectory),
           branch != "HEAD" {
            return branch
        }
        return await branchPointingAtHead(in: swiftDirectory)
    }

    /// Parses the current branch from `<repo>/.git/HEAD` without spawning git. Returns `nil` for a
    /// detached HEAD (a bare SHA) or if the file can't be read, letting the git fallback try.
    private static func branchFromGitHead(in swiftDirectory: URL) -> String? {
        let dotGit = swiftDirectory.appendingPathComponent(".git")

        // `.git` is normally a directory, but for a worktree/submodule it's a file whose contents are
        // "gitdir: <path>" pointing at the real git directory.
        var gitDirectory = dotGit
        if (try? dotGit.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false,
           let pointer = try? String(contentsOf: dotGit, encoding: .utf8),
           let line = pointer.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") }) {
            let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            gitDirectory = URL(fileURLWithPath: path, relativeTo: swiftDirectory).standardizedFileURL
        }

        let head = gitDirectory.appendingPathComponent("HEAD")
        guard let contents = try? String(contentsOf: head, encoding: .utf8) else { return nil }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)

        // "ref: refs/heads/<branch>" on a branch; a bare 40-char SHA when detached.
        guard trimmed.hasPrefix("ref:") else { return nil }
        let ref = trimmed.dropFirst("ref:".count).trimmingCharacters(in: .whitespaces)
        let headsPrefix = "refs/heads/"
        guard ref.hasPrefix(headsPrefix) else { return nil }
        let branch = String(ref.dropFirst(headsPrefix.count))
        return branch.isEmpty ? nil : branch
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

private struct ParsedCheckoutConfig {
    public let defaultScheme: String
    public let schemes: [ParsedScheme]
}

private struct ParsedScheme {
    public let name: String
    public let aliases: [String]
    public let swiftBranch: String
}
