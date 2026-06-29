import Foundation

enum CheckoutSchemeResolver {
    static func resolve(
        swiftDirectory: URL,
        overrideScheme: String? = nil
    ) -> (scheme: String, branch: String, source: SchemeResolutionSource) {
        if let override = overrideScheme?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            let branch = currentBranch(in: swiftDirectory) ?? override
            return (override, branch, .manualOverride)
        }

        let branch = currentBranch(in: swiftDirectory) ?? "main"
        let configURL = swiftDirectory
            .appendingPathComponent("utils/update_checkout/update-checkout-config.json")

        guard let config = loadConfig(at: configURL) else {
            return (fallbackScheme(for: branch), branch, .branchFallback)
        }

        let defaultScheme = config.defaultScheme
        let schemes = config.schemes

        if let match = schemes.first(where: { $0.name == branch }) {
            return (match.name, branch, .branchName)
        }

        if let match = schemes.first(where: { $0.aliases.contains(branch) }) {
            return (match.name, branch, .alias)
        }

        if let match = schemes.first(where: { $0.swiftBranch == branch }) {
            return (match.name, branch, .swiftRepoBranch)
        }

        if schemes.contains(where: { $0.name == defaultScheme }) {
            return (defaultScheme, branch, .defaultScheme)
        }

        return (fallbackScheme(for: branch), branch, .branchFallback)
    }

    static func availableSchemes(swiftDirectory: URL) -> [String] {
        let configURL = swiftDirectory
            .appendingPathComponent("utils/update_checkout/update-checkout-config.json")
        guard let config = loadConfig(at: configURL) else { return ["main"] }
        return config.schemes.map(\.name).sorted()
    }

    private static func fallbackScheme(for branch: String) -> String {
        if branch.hasPrefix("release/") { return branch }
        return "main"
    }

    private static func currentBranch(in swiftDirectory: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", swiftDirectory.path, "rev-parse", "--abbrev-ref", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let branch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let branch, branch != "HEAD" else { return nil }
            return branch
        } catch {
            return nil
        }
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

nonisolated enum SchemeResolutionSource: String, Sendable, Equatable {
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
            "Feature branch detected; using the default scheme from update-checkout-config.json. Dependencies will align to your swift commit timestamp."
        case .branchFallback:
            "Could not read update-checkout-config.json; using a best-guess scheme."
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