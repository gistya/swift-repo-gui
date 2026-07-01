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
    var reloadPending: Bool = false

    var isValid: Bool { projectInfo != nil }
}

struct ProjectMachine: StateMachine {
    typealias Context = ProjectContext
    typealias StateID = ProjectState
    typealias EventID = ProjectEvent

    var context: ProjectContext { .init() }

    var machine: some XStateMachine {
        XState(.ready) {
            Always(to: .loading)
                .when { $0.reloadPending && !$0.projectPath.isEmpty }
                .action { ctx in
                    var next = ctx
                    next.reloadPending = false
                    next.validationMessage = nil
                    return next
                }

            XTransition(on: ProjectEvent.setPath, to: .ready).when { _, event in
                guard case let .setPath(path)? = event else { return false }
                return path.isEmpty
            }.action { args, _ in
                var ctx = args.context
                guard case let .setPath(path)? = args.event else { return ctx }
                ctx.projectPath = path
                UserDefaults.standard.set(path, forKey: "projectPath")
                ctx.projectInfo = nil
                ctx.validationMessage = "Choose your swift-project directory to get started."
                return ctx
            }
            XTransition(on: ProjectEvent.setPath, to: .ready).when { _, event in
                guard case let .setPath(path)? = event else { return false }
                return !path.isEmpty
            }.action { args, _ in
                var ctx = args.context
                guard case let .setPath(path)? = args.event else { return ctx }
                ctx.projectPath = path
                UserDefaults.standard.set(path, forKey: "projectPath")
                ctx.inspectMode = .fullInspect
                ctx.reloadPending = true
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
            XTransition(on: ProjectEvent.setCheckoutSchemeOverride, to: .ready).when { !$0.projectPath.isEmpty }
                .action { args, _ in
                    var ctx = args.context
                    if case let .setCheckoutSchemeOverride(scheme)? = args.event {
                        ctx.checkoutSchemeOverride = scheme
                        UserDefaults.standard.set(scheme, forKey: "checkoutSchemeOverride")
                        ctx.inspectMode = .fullInspect
                        ctx.reloadPending = true
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
            XTransition(on: .refresh, to: .ready).when { !$0.projectPath.isEmpty }.action { args, _ in
                var ctx = args.context
                ctx.inspectMode = .fullInspect
                ctx.reloadPending = true
                ctx.validationMessage = nil
                return ctx
            }

            XTransition(on: .captureRevisions, to: .ready).when { $0.projectInfo == nil }.action { args, _ in
                var ctx = args.context
                ctx.validationMessage = ProjectInspectFailure.projectNotLoaded.errorDescription
                return ctx
            }
            XTransition(on: .captureRevisions, to: .ready).when { $0.projectInfo != nil }.action { args, _ in
                var ctx = args.context
                ctx.inspectMode = .revisionsOnly
                ctx.reloadPending = true
                return ctx
            }

            XTransition(on: .restore, to: .ready).when { $0.projectPath.isEmpty }.action { args, _ in
                var ctx = args.context
                ctx.projectInfo = nil
                ctx.validationMessage = "Choose your swift-project directory to get started."
                return ctx
            }
            XTransition(on: .restore, to: .ready).when { !$0.projectPath.isEmpty }.action { args, _ in
                var ctx = args.context
                ctx.inspectMode = .fullInspect
                ctx.reloadPending = true
                ctx.validationMessage = nil
                return ctx
            }
        }
        .initial()

        XState(.loading) {
            Invoke(id: "inspect", run: { scope in
                do {
                    guard let input = scope.input?.get(ProjectInspectInput.self) else {
                        throw ProjectInspectFailure.missingInput
                    }

                    switch input.mode {
                    case .fullInspect:
                        let snapshot = try ProjectService.validateProject(
                            projectPath: input.projectPath,
                            checkoutSchemeOverride: input.checkoutSchemeOverride
                        )
                        let repositories = await ProjectService.fetchRevisions(for: snapshot.candidates)
                        return ProjectInspectOutput(mode: input.mode, snapshot: snapshot, repositories: repositories)
                    case .revisionsOnly:
                        let repositories = await ProjectService.fetchRevisions(for: input.existingCandidates)
                        return ProjectInspectOutput(mode: input.mode, snapshot: nil, repositories: repositories)
                    }
                } catch {
                    throw PresentableError(error)
                }
            })
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
            .onDone(to: .ready, reading: ProjectInspectOutput.self) { output, ctx in
                Self.applyInspectResult(output, to: ctx)
            }
            .onError(to: .ready) { error, ctx in
                var next = ctx
                if ctx.inspectMode == .fullInspect {
                    next.projectInfo = nil
                }
                next.validationMessage = error
                return next
            }

            XTransition(on: ProjectEvent.setBuildSubdir, to: .loading).action { args, _ in
                var ctx = args.context
                if case let .setBuildSubdir(subdir)? = args.event {
                    ctx.selectedBuildSubdir = subdir
                    UserDefaults.standard.set(subdir, forKey: "selectedBuildSubdir")
                }
                return ctx
            }

            XTransition(on: ProjectEvent.setPath, to: .ready).action { args, _ in
                Self.queueReload(context: args.context, event: args.event, mode: .fullInspect)
            }
            XTransition(on: .refresh, to: .ready).when { !$0.projectPath.isEmpty }.action { args, _ in
                Self.queueReload(context: args.context, event: args.event, mode: .fullInspect)
            }
            XTransition(on: ProjectEvent.setCheckoutSchemeOverride, to: .ready).when { !$0.projectPath.isEmpty }
                .action { args, _ in
                    var ctx = args.context
                    if case let .setCheckoutSchemeOverride(scheme)? = args.event {
                        ctx.checkoutSchemeOverride = scheme
                        UserDefaults.standard.set(scheme, forKey: "checkoutSchemeOverride")
                    }
                    return Self.queueReload(context: ctx, event: args.event, mode: .fullInspect)
                }
            XTransition(on: .captureRevisions, to: .ready).when { $0.projectInfo != nil }.action { args, _ in
                Self.queueReload(context: args.context, event: args.event, mode: .revisionsOnly)
            }
            XTransition(on: .restore, to: .ready).when { !$0.projectPath.isEmpty }.action { args, _ in
                Self.queueReload(context: args.context, event: args.event, mode: .fullInspect)
            }
        }
    }

    private static func queueReload(
        context: ProjectContext,
        event: ProjectEvent?,
        mode: ProjectInspectMode
    ) -> ProjectContext {
        var ctx = context
        ctx.inspectMode = mode
        ctx.reloadPending = true
        ctx.validationMessage = nil
        if case let .setPath(path)? = event {
            ctx.projectPath = path
            UserDefaults.standard.set(path, forKey: "projectPath")
        }
        return ctx
    }

    private static func applyInspectResult(_ output: ProjectInspectOutput, to ctx: ProjectContext) -> ProjectContext {
        var next = ctx
        let sorted = output.repositories

        switch output.mode {
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
            if let snapshot = output.snapshot {
                next.projectInfo = ProjectService.makeProjectInfo(snapshot: snapshot, repositories: sorted)
                next.validationMessage = nil
                if next.selectedBuildSubdir.isEmpty || !snapshot.detectedBuildSubdirs.contains(next.selectedBuildSubdir) {
                    next.selectedBuildSubdir = snapshot.detectedBuildSubdirs.first ?? ""
                    UserDefaults.standard.set(next.selectedBuildSubdir, forKey: "selectedBuildSubdir")
                }
            } else {
                next.projectInfo = nil
                next.validationMessage = "Project inspection did not return a validated snapshot."
            }
        }

        return next
    }
}
