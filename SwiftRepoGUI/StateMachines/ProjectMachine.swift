import CompositionalInit
import Foundation
import SwiftXState

nonisolated enum ProjectState: String, StateIdentifying {
    case ready
    case loading
    static var _blank: ProjectState { .ready }
}

nonisolated enum ProjectEvent: EventIdentifying {
    case setPath(String)
    case setBuildSubdir(String)
    case setCheckoutSchemeOverride(String)
    case refresh
    case captureRevisions
    case restore
    static var _blank: ProjectEvent { .refresh }
}

nonisolated struct ProjectContext: Sendable, Equatable {
    var projectPath: String = UserDefaults.standard.string(forKey: "projectPath") ?? ""
    var selectedBuildSubdir: String = UserDefaults.standard.string(forKey: "selectedBuildSubdir") ?? ""
    var checkoutSchemeOverride: String = UserDefaults.standard.string(forKey: "checkoutSchemeOverride") ?? ""
    var projectInfo: SwiftProjectInfo?
    var validationMessage: String?
    var revisionsBeforeUpdate: [String: String] = [:]
    var inspectMode: ProjectInspectMode = .fullInspect

    var isValid: Bool { projectInfo != nil }
}

struct ProjectMachine: StateMachine {
    typealias Context = ProjectContext
    typealias StateID = ProjectState
    typealias EventID = ProjectEvent

    var context: ProjectContext { .init() }

    var machine: some XStateMachine {
        XState(.ready) {
            XTransition(on: ProjectEvent.setPath, to: .ready).action { args, _ in
                var ctx = args.context
                guard case let .setPath(path)? = args.event else { return ctx }
                ctx.projectPath = path
                UserDefaults.standard.set(path, forKey: "projectPath")
                if path.isEmpty {
                    ctx.projectInfo = nil
                    ctx.validationMessage = "Choose your swift-project directory to get started."
                }
                return ctx
            }
            XTransition(on: ProjectEvent.setPath, to: .loading).when { _, event in
                guard case let .setPath(path)? = event else { return false }
                return !path.isEmpty
            }.action { args, _ in
                var ctx = args.context
                guard case let .setPath(path)? = args.event else { return ctx }
                ctx.projectPath = path
                UserDefaults.standard.set(path, forKey: "projectPath")
                ctx.inspectMode = .fullInspect
                ctx.validationMessage = nil
                return ctx
            }

            XTransition(on: ProjectEvent.setBuildSubdir, to: .ready).action { args, _ in
                var ctx = args.context
                if case let .setBuildSubdir(subdir)? = args.event {
                    ctx.selectedBuildSubdir = subdir
                    UserDefaults.standard.set(subdir, forKey: "selectedBuildSubdir")
                }
                return ctx
            }

            XTransition(on: ProjectEvent.setCheckoutSchemeOverride, to: .ready).when { $0.projectPath.isEmpty }
                .action { args, _ in
                    var ctx = args.context
                    if case let .setCheckoutSchemeOverride(scheme)? = args.event {
                        ctx.checkoutSchemeOverride = scheme
                        UserDefaults.standard.set(scheme, forKey: "checkoutSchemeOverride")
                    }
                    return ctx
                }
            XTransition(on: ProjectEvent.setCheckoutSchemeOverride, to: .loading).when { !$0.projectPath.isEmpty }
                .action { args, _ in
                    var ctx = args.context
                    if case let .setCheckoutSchemeOverride(scheme)? = args.event {
                        ctx.checkoutSchemeOverride = scheme
                        UserDefaults.standard.set(scheme, forKey: "checkoutSchemeOverride")
                        ctx.inspectMode = .fullInspect
                        ctx.validationMessage = nil
                    }
                    return ctx
                }

            XTransition(on: .refresh, to: .ready).when { $0.projectPath.isEmpty }.action { args, _ in
                var ctx = args.context
                ctx.projectInfo = nil
                ctx.validationMessage = "Choose your swift-project directory to get started."
                return ctx
            }
            XTransition(on: .refresh, to: .loading).when { !$0.projectPath.isEmpty }.action { args, _ in
                var ctx = args.context
                ctx.inspectMode = .fullInspect
                ctx.validationMessage = nil
                return ctx
            }

            XTransition(on: .captureRevisions, to: .loading).when { $0.projectInfo != nil }.action { args, _ in
                var ctx = args.context
                ctx.inspectMode = .revisionsOnly
                return ctx
            }

            XTransition(on: .restore, to: .ready).when { $0.projectPath.isEmpty }.action { args, _ in
                var ctx = args.context
                ctx.projectInfo = nil
                ctx.validationMessage = "Choose your swift-project directory to get started."
                return ctx
            }
            XTransition(on: .restore, to: .loading).when { !$0.projectPath.isEmpty }.action { args, _ in
                var ctx = args.context
                ctx.inspectMode = .fullInspect
                ctx.validationMessage = nil
                return ctx
            }
        }
        .initial()

        XState(.loading) {
            Invoke(
                id: "inspect",
                source: fromTaskGroup { scope in
                    guard let input = scope.input?.get(ProjectInspectInput.self) else {
                        throw ProjectInspectFailure.missingInput
                    }

                    let candidates: [RepositoryCandidate]
                    switch input.mode {
                    case .fullInspect:
                        let snapshot = try ProjectService.validateProject(
                            projectPath: input.projectPath,
                            checkoutSchemeOverride: input.checkoutSchemeOverride
                        )
                        candidates = snapshot.candidates
                    case .revisionsOnly:
                        candidates = input.existingCandidates
                    }

                    return try await scope.runGroup(
                        candidates.map { candidate in
                            { @Sendable in
                                SwiftRepository(
                                    name: candidate.name,
                                    path: candidate.path,
                                    currentRevision: ProjectService.currentRevision(at: candidate.path)
                                )
                            }
                        }
                    )
                }
            )
            .input { ctx in
                SendableValue(
                    ProjectInspectInput(
                        projectPath: ctx.projectPath,
                        checkoutSchemeOverride: ctx.checkoutSchemeOverride,
                        selectedBuildSubdir: ctx.selectedBuildSubdir,
                        mode: ctx.inspectMode,
                        existingCandidates: ctx.projectInfo?.repositories.map {
                            RepositoryCandidate(name: $0.name, path: $0.path)
                        } ?? []
                    )
                )
            }
            .onDone(to: .ready, reading: [SwiftRepository].self) { repositories, ctx in
                Self.applyInspectResult(repositories, to: ctx)
            }
            .onError(to: .ready) { error, ctx in
                var next = ctx
                if ctx.inspectMode == .fullInspect {
                    next.projectInfo = nil
                }
                next.validationMessage = error
                return next
            }
        }
    }

    private static func applyInspectResult(_ repositories: [SwiftRepository], to ctx: ProjectContext) -> ProjectContext {
        var next = ctx
        let sorted = ProjectService.sortRepositories(repositories)

        switch next.inspectMode {
        case .revisionsOnly:
            next.revisionsBeforeUpdate = Dictionary(
                uniqueKeysWithValues: sorted.compactMap { repo in
                    guard let revision = repo.currentRevision else { return nil }
                    return (repo.name, revision)
                }
            )
            if let info = next.projectInfo {
                next.projectInfo = info.replacingRepositories(sorted)
            }
        case .fullInspect:
            do {
                let snapshot = try ProjectService.validateProject(
                    projectPath: next.projectPath,
                    checkoutSchemeOverride: next.checkoutSchemeOverride
                )
                next.projectInfo = ProjectService.makeProjectInfo(snapshot: snapshot, repositories: sorted)
                next.validationMessage = nil
                if next.selectedBuildSubdir.isEmpty || !snapshot.detectedBuildSubdirs.contains(next.selectedBuildSubdir) {
                    next.selectedBuildSubdir = snapshot.detectedBuildSubdirs.first ?? ""
                    UserDefaults.standard.set(next.selectedBuildSubdir, forKey: "selectedBuildSubdir")
                }
            } catch {
                next.projectInfo = nil
                next.validationMessage = error.localizedDescription
            }
        }

        return next
    }
}