import Foundation

nonisolated struct SwiftRepository: Identifiable, Hashable, Sendable, Equatable {
    let name: String
    let path: URL
    var currentRevision: String?
    var isPrimary: Bool { name == "swift" }

    var id: String { name }
}

nonisolated struct SwiftProjectInfo: Sendable, Equatable {
    let root: URL
    let swiftDirectory: URL
    let buildScript: URL
    let updateCheckout: URL
    let buildRoot: URL
    let repositories: [SwiftRepository]
    let detectedBuildSubdirs: [String]
    let swiftBuildDirectoryName: String
    let checkoutScheme: String
    let swiftBranch: String
    let schemeResolutionSource: SchemeResolutionSource
    let availableCheckoutSchemes: [String]

    func replacingRepositories(_ repositories: [SwiftRepository]) -> SwiftProjectInfo {
        SwiftProjectInfo(
            root: root,
            swiftDirectory: swiftDirectory,
            buildScript: buildScript,
            updateCheckout: updateCheckout,
            buildRoot: buildRoot,
            repositories: repositories,
            detectedBuildSubdirs: detectedBuildSubdirs,
            swiftBuildDirectoryName: swiftBuildDirectoryName,
            checkoutScheme: checkoutScheme,
            swiftBranch: swiftBranch,
            schemeResolutionSource: schemeResolutionSource,
            availableCheckoutSchemes: availableCheckoutSchemes
        )
    }
}

enum SwiftProjectError: LocalizedError {
    case invalidRoot
    case missingSwiftDirectory
    case missingBuildScript
    case missingUpdateCheckout
    case noBuildSubdirectory

    var errorDescription: String? {
        switch self {
        case .invalidRoot: "Select a directory that contains the swift checkout."
        case .missingSwiftDirectory: "Could not find swift/ inside the selected directory."
        case .missingBuildScript: "Could not find swift/utils/build-script."
        case .missingUpdateCheckout: "Could not find swift/utils/update-checkout."
        case .noBuildSubdirectory: "No Ninja build directory found under build/."
        }
    }
}

enum ProjectService {
    static func inspect(projectPath: String, checkoutSchemeOverride: String = "") throws -> SwiftProjectInfo {
        let snapshot = try validateProject(
            projectPath: projectPath,
            checkoutSchemeOverride: checkoutSchemeOverride
        )
        let repositories = snapshot.candidates.map { candidate in
            SwiftRepository(
                name: candidate.name,
                path: candidate.path,
                currentRevision: currentRevision(at: candidate.path)
            )
        }
        return makeProjectInfo(snapshot: snapshot, repositories: sortRepositories(repositories))
    }

    static func validateProject(
        projectPath: String,
        checkoutSchemeOverride: String = ""
    ) throws -> ValidatedProjectSnapshot {
        let root = URL(fileURLWithPath: (projectPath as NSString).expandingTildeInPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SwiftProjectError.invalidRoot
        }

        let swiftDirectory = root.appendingPathComponent("swift", isDirectory: true)
        guard FileManager.default.fileExists(atPath: swiftDirectory.path) else {
            throw SwiftProjectError.missingSwiftDirectory
        }

        let buildScript = swiftDirectory.appendingPathComponent("utils/build-script")
        guard FileManager.default.fileExists(atPath: buildScript.path) else {
            throw SwiftProjectError.missingBuildScript
        }

        let updateCheckout = swiftDirectory.appendingPathComponent("utils/update-checkout")
        guard FileManager.default.fileExists(atPath: updateCheckout.path) else {
            throw SwiftProjectError.missingUpdateCheckout
        }

        let buildRoot = root.appendingPathComponent("build", isDirectory: true)
        let detectedBuildSubdirs = detectBuildSubdirs(in: buildRoot)
        let platform = platformName
        let arch = machineArch
        let swiftBuildDirectoryName = "swift-\(platform)-\(arch)"
        let candidates = listRepositoryCandidates(in: root)
        let schemeResolution = CheckoutSchemeResolver.resolve(
            swiftDirectory: swiftDirectory,
            overrideScheme: checkoutSchemeOverride.isEmpty ? nil : checkoutSchemeOverride
        )
        let availableSchemes = CheckoutSchemeResolver.availableSchemes(swiftDirectory: swiftDirectory)

        return ValidatedProjectSnapshot(
            root: root,
            swiftDirectory: swiftDirectory,
            buildScript: buildScript,
            updateCheckout: updateCheckout,
            buildRoot: buildRoot,
            candidates: candidates,
            detectedBuildSubdirs: detectedBuildSubdirs,
            swiftBuildDirectoryName: swiftBuildDirectoryName,
            checkoutScheme: schemeResolution.scheme,
            swiftBranch: schemeResolution.branch,
            schemeResolutionSource: schemeResolution.source,
            availableCheckoutSchemes: availableSchemes
        )
    }

    static func makeProjectInfo(
        snapshot: ValidatedProjectSnapshot,
        repositories: [SwiftRepository]
    ) -> SwiftProjectInfo {
        SwiftProjectInfo(
            root: snapshot.root,
            swiftDirectory: snapshot.swiftDirectory,
            buildScript: snapshot.buildScript,
            updateCheckout: snapshot.updateCheckout,
            buildRoot: snapshot.buildRoot,
            repositories: repositories,
            detectedBuildSubdirs: snapshot.detectedBuildSubdirs,
            swiftBuildDirectoryName: snapshot.swiftBuildDirectoryName,
            checkoutScheme: snapshot.checkoutScheme,
            swiftBranch: snapshot.swiftBranch,
            schemeResolutionSource: snapshot.schemeResolutionSource,
            availableCheckoutSchemes: snapshot.availableCheckoutSchemes
        )
    }

    static func repositoryRevisions(for project: SwiftProjectInfo) -> [String: String] {
        var revisions: [String: String] = [:]
        for repo in project.repositories {
            revisions[repo.name] = currentRevision(at: repo.path)
        }
        return revisions
    }

    static func changedRepositories(
        in project: SwiftProjectInfo,
        since revisions: [String: String]
    ) -> [SwiftRepository] {
        project.repositories.filter { repo in
            guard let before = revisions[repo.name] else { return true }
            let after = currentRevision(at: repo.path) ?? ""
            return before != after
        }
    }

    static func listRepositoryCandidates(in root: URL) -> [RepositoryCandidate] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return children.compactMap { url -> RepositoryCandidate? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let gitDir = url.appendingPathComponent(".git")
            guard FileManager.default.fileExists(atPath: gitDir.path) else { return nil }
            return RepositoryCandidate(name: url.lastPathComponent, path: url)
        }
        .sorted { lhs, rhs in
            if lhs.isPrimary { return true }
            if rhs.isPrimary { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func sortRepositories(_ repositories: [SwiftRepository]) -> [SwiftRepository] {
        repositories.sorted { lhs, rhs in
            if lhs.isPrimary { return true }
            if rhs.isPrimary { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func discoverRepositories(in root: URL) -> [SwiftRepository] {
        listRepositoryCandidates(in: root).map { candidate in
            SwiftRepository(
                name: candidate.name,
                path: candidate.path,
                currentRevision: currentRevision(at: candidate.path)
            )
        }
    }

    static func currentRevision(at repoPath: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoPath.path, "rev-parse", "--short", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    static func detectBuildSubdirs(in buildRoot: URL) -> [String] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: buildRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let swiftDirName = "swift-\(platformName)-\(machineArch)"

        return children.compactMap { url -> String? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let swiftBuild = url.appendingPathComponent(swiftDirName, isDirectory: true)
            guard FileManager.default.fileExists(atPath: swiftBuild.path) else { return nil }
            return url.lastPathComponent
        }
        .sorted()
    }

    static var platformName: String {
        #if os(macOS)
        "macosx"
        #elseif os(Linux)
        "linux"
        #else
        "unknown"
        #endif
    }

    static var machineArch: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    static func repoNinjaDirectoryName(_ repoName: String, platform: String, arch: String) -> String {
        switch repoName {
        case "swift": "swift-\(platform)-\(arch)"
        case "llvm-project": "llvm-\(platform)-\(arch)"
        case "cmark": "cmark-\(platform)-\(arch)"
        case "llbuild": "llbuild-\(platform)-\(arch)"
        case "swiftpm": "swiftpm-\(platform)-\(arch)"
        case "swift-driver": "swiftdriver-\(platform)-\(arch)"
        case "swift-syntax": "swiftsyntax-\(platform)-\(arch)"
        default: "\(repoName)-\(platform)-\(arch)"
        }
    }
}