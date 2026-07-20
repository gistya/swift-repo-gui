import Foundation

/// Which Xcode (and optionally which Swift toolchain) the app's spawned build commands should use.
///
/// Applied as `DEVELOPER_DIR` / `TOOLCHAINS` on the CHILD PROCESS only, so choosing here never touches
/// the machine-wide `xcode-select` or your shell — you can build the toolchain with one Xcode from this
/// app while working in a different one everywhere else.
nonisolated public struct ToolchainSelection: Sendable, Equatable {
    /// Path to an `Xcode.app` (or an already-resolved `…/Contents/Developer`). Empty = system default.
    var developerDir: String = ""
    /// A toolchain's `CFBundleIdentifier`, for `TOOLCHAINS`. Empty = that Xcode's default toolchain.
    var toolchainIdentifier: String = ""

    static let systemDefault = ToolchainSelection()

    static let developerDirDefaultsKey = "buildDeveloperDir"
    static let toolchainIdentifierDefaultsKey = "buildToolchainIdentifier"

    /// The persisted selection (what the Build Settings pickers write).
    public static func current(_ defaults: UserDefaults = .standard) -> ToolchainSelection {
        ToolchainSelection(
            developerDir: defaults.string(forKey: developerDirDefaultsKey) ?? "",
            toolchainIdentifier: defaults.string(forKey: toolchainIdentifierDefaultsKey) ?? ""
        )
    }

    /// The `DEVELOPER_DIR` value — accepts either an `Xcode.app` path or a Developer dir. `nil` when
    /// nothing is chosen.
    var resolvedDeveloperDir: String? {
        let trimmed = developerDir.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix("/Contents/Developer") { return trimmed }
        if trimmed.hasSuffix(".app") { return trimmed + "/Contents/Developer" }
        return trimmed
    }

    var trimmedToolchainIdentifier: String? {
        let trimmed = toolchainIdentifier.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Directories to front-load onto `PATH` so a bare `swift` / `swiftc` / `clang` resolves to the
    /// chosen toolchain rather than whichever shim (swiftly, Homebrew) happens to come first —
    /// `DEVELOPER_DIR` alone only governs `xcrun`-mediated lookups. An explicitly chosen toolchain
    /// outranks the Xcode's bundled one. Only directories that actually exist are added.
    func pathPrefixes(toolchains: [InstalledToolchain]) -> [String] {
        var candidates: [String] = []
        if let identifier = trimmedToolchainIdentifier,
           let selected = toolchains.first(where: { $0.identifier == identifier }) {
            candidates.append(selected.path + "/usr/bin")
        }
        if let developerDir = resolvedDeveloperDir {
            candidates.append(developerDir + "/Toolchains/XcodeDefault.xctoolchain/usr/bin")
            candidates.append(developerDir + "/usr/bin")
        }
        return candidates.filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Overlay this selection onto a child-process environment.
    ///
    /// When nothing is selected we deliberately REMOVE any inherited `DEVELOPER_DIR`/`TOOLCHAINS`, so a
    /// build is deterministic (it follows `xcode-select`) instead of depending on however the app
    /// happened to be launched — which is the whole point of choosing the toolchain in-app.
    func apply(
        to environment: inout [String: String],
        toolchains: [InstalledToolchain] = InstalledDeveloperTools.toolchains()
    ) {
        if let developerDir = resolvedDeveloperDir {
            environment["DEVELOPER_DIR"] = developerDir
        } else {
            environment.removeValue(forKey: "DEVELOPER_DIR")
        }
        if let toolchain = trimmedToolchainIdentifier {
            environment["TOOLCHAINS"] = toolchain
        } else {
            environment.removeValue(forKey: "TOOLCHAINS")
        }

        PathEnvironment.frontLoad(pathPrefixes(toolchains: toolchains), in: &environment)
    }

    /// One-line description for the build log header / settings summary.
    var summary: String {
        let xcode = resolvedDeveloperDir.map { "DEVELOPER_DIR=\($0)" } ?? "Xcode: system default (xcode-select)"
        guard let toolchain = trimmedToolchainIdentifier else { return xcode }
        return "\(xcode)  TOOLCHAINS=\(toolchain)"
    }
}

/// An `Xcode.app` found on disk.
nonisolated struct InstalledXcode: Identifiable, Sendable, Equatable {
    let appPath: String
    let name: String
    let version: String
    let build: String

    var id: String { appPath }
    var developerDir: String { appPath + "/Contents/Developer" }
    var display: String {
        let versionText = build.isEmpty ? "Xcode \(version)" : "Xcode \(version) (\(build))"
        return "\(versionText) — \(name)"
    }
}

/// A `*.xctoolchain` found on disk, selectable via `TOOLCHAINS`.
nonisolated struct InstalledToolchain: Identifiable, Sendable, Equatable {
    let identifier: String
    let name: String
    let path: String

    var id: String { identifier }
    var display: String { name.isEmpty ? identifier : name }
}

/// Locates the Xcodes and Swift toolchains installed on this machine, so the user can pick one instead
/// of inheriting whatever the environment happens to point at.
nonisolated enum InstalledDeveloperTools {
    /// Every `Xcode.app` under /Applications (and ~/Applications), newest version first.
    static func xcodes() -> [InstalledXcode] {
        var found: [InstalledXcode] = []
        var seen = Set<String>()
        for root in ["/Applications", NSHomeDirectory() + "/Applications"] {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let appPath = root + "/" + entry
                // A real Xcode, not just any app: it must ship a Developer dir with xcodebuild.
                guard FileManager.default.fileExists(atPath: appPath + "/Contents/Developer/usr/bin/xcodebuild"),
                      seen.insert(appPath).inserted else { continue }
                found.append(InstalledXcode(
                    appPath: appPath,
                    name: entry,
                    version: plistString("CFBundleShortVersionString", at: appPath + "/Contents/Info.plist") ?? "?",
                    build: plistString("ProductBuildVersion", at: appPath + "/Contents/version.plist") ?? ""
                ))
            }
        }
        return found.sorted {
            let byVersion = $0.version.localizedStandardCompare($1.version)
            if byVersion != .orderedSame { return byVersion == .orderedDescending }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Every installed `*.xctoolchain`, deduped by bundle identifier (so an alias like
    /// `swift-latest.xctoolchain`, which shares its target's identifier, collapses into one entry).
    static func toolchains() -> [InstalledToolchain] {
        var found: [InstalledToolchain] = []
        var seenIdentifiers = Set<String>()
        for root in ["/Library/Developer/Toolchains", NSHomeDirectory() + "/Library/Developer/Toolchains"] {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            // Sorted so a real toolchain is visited before an alias and therefore wins the dedupe.
            for entry in entries.sorted() where entry.hasSuffix(".xctoolchain") {
                let path = root + "/" + entry
                // swift.org toolchains carry Info.plist; Xcode-bundled ones use ToolchainInfo.plist.
                let plists = [path + "/Info.plist", path + "/ToolchainInfo.plist"]
                guard let identifier = plists.lazy.compactMap({ plistString("CFBundleIdentifier", at: $0) }).first,
                      !identifier.isEmpty,
                      seenIdentifiers.insert(identifier).inserted else { continue }
                let name = plists.lazy.compactMap { plistString("DisplayName", at: $0) }.first
                found.append(InstalledToolchain(identifier: identifier, name: name ?? entry, path: path))
            }
        }
        return found.sorted { $0.display.localizedStandardCompare($1.display) == .orderedAscending }
    }

    private static func plistString(_ key: String, at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist[key] as? String
    }
}
