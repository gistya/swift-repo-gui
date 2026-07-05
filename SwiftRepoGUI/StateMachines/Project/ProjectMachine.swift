import Foundation
import SwiftXState

struct ProjectMachine: StateMachine {
    typealias Context = ProjectContext
    typealias StateID = ProjectState
    typealias EventID = ProjectEvent

    var context: ProjectContext { .init() }

    var machine: some XStateMachine {
        State(.ready) {
            Always(to: .error)
                .when(Self.hasValidationError)
            Always(to: .reloading)
                .when { $0.reloadPending && !$0.projectPath.isEmpty }
            for transition in Self.projectInputTransitions() {
                transition
            }
        }
        .initial()

        State(.error) {
            Always(to: .reloading)
                .when { $0.reloadPending && !$0.projectPath.isEmpty }
            for transition in Self.projectInputTransitions() {
                transition
            }
        }

        State(.loading) {
            State(.reloading) {
                Always(to: .refreshing)
                    .when { !$0.projectPath.isEmpty }
                    .action(Self.clearReloadRequest)
                Always(to: .ready)
                    .when { $0.projectPath.isEmpty }
            }
            .initial()

            State(.refreshing) {
                Invoke(id: "inspect", run: { scope in
                    do {
                        guard let input = scope.input?.get(ProjectInspectInput.self) else {
                            throw ProjectInspectFailure.missingInput
                        }

                        switch input.mode {
                        case .fullInspect:
                            let snapshot = try await ProjectService.validateProject(
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
                .onError(to: .error) { error, ctx in
                    var next = ctx
                    if ctx.inspectMode == .fullInspect {
                        next.projectInfo = nil
                    }
                    next.reloadPending = false
                    next.validationMessage = error
                    return next
                }

                Transition(on: ProjectEvent.setBuildSubdir, to: .refreshing).action { args, _ in
                    Self.applyBuildSubdir(args.event, to: args.context)
                }

                Transition(on: ProjectEvent.setPath, to: .ready)
                    .when(Self.eventPathIsEmpty)
                    .action { args, _ in Self.applyEmptyPath(args.event, to: args.context) }

                Transition(on: ProjectEvent.setPath, to: .reloading)
                    .when { _, event in !Self.pathEventIsEmpty(event) }
                    .action { args, _ in Self.queueReload(context: args.context, event: args.event, mode: .fullInspect) }

                Transition(on: .refresh, to: .reloading)
                    .when { !$0.projectPath.isEmpty }
                    .action { args, _ in Self.queueReload(context: args.context, event: args.event, mode: .fullInspect) }

                Transition(on: ProjectEvent.setCheckoutSchemeOverride, to: .reloading)
                    .when { !$0.projectPath.isEmpty }
                    .action { args, _ in Self.queueReload(context: args.context, event: args.event, mode: .fullInspect) }

                Transition(on: .captureRevisions, to: .reloading)
                    .when { $0.projectInfo != nil }
                    .action { args, _ in Self.queueReload(context: args.context, event: args.event, mode: .revisionsOnly) }

                Transition(on: .restore, to: .reloading)
                    .when { !$0.projectPath.isEmpty }
                    .action { args, _ in Self.queueReload(context: args.context, event: args.event, mode: .fullInspect) }
            }
        }
    }

    private static func projectInputTransitions() -> [Transition] {
        [
            Transition(on: ProjectEvent.setPath, to: .ready)
                .when(Self.eventPathIsEmpty)
                .action { args, _ in Self.applyEmptyPath(args.event, to: args.context) },

            Transition(on: ProjectEvent.setPath, to: .reloading)
                .when { _, event in
                    guard case let .setPath(path)? = event else { return false }
                    return !path.isEmpty
                }
                .action { args, _ in Self.queueReload(context: args.context, event: args.event, mode: .fullInspect) },

            Transition(on: ProjectEvent.setBuildSubdir, to: .ready)
                .action { args, _ in Self.applyBuildSubdir(args.event, to: args.context) },

            Transition(on: ProjectEvent.setCheckoutSchemeOverride, to: .ready)
                .when { $0.projectPath.isEmpty }
                .action { args, _ in Self.applyCheckoutScheme(args.event, to: args.context) },

            Transition(on: ProjectEvent.setCheckoutSchemeOverride, to: .reloading)
                .when { !$0.projectPath.isEmpty }
                .action { args, _ in Self.queueReload(context: args.context, event: args.event, mode: .fullInspect) },

            Transition(on: .refresh, to: .ready)
                .when { $0.projectPath.isEmpty }
                .action { args, _ in Self.applyMissingProjectMessage(to: args.context) },

            Transition(on: .refresh, to: .refreshing)
                .when { !$0.projectPath.isEmpty }
                .action { args, _ in Self.prepareInspect(context: args.context, mode: .fullInspect) },

            Transition(on: .captureRevisions, to: .error)
                .when { $0.projectInfo == nil }
                .action { args, _ in
                    var ctx = args.context
                    ctx.validationMessage = ProjectInspectFailure.projectNotLoaded.errorDescription
                    return ctx
                },

            Transition(on: .captureRevisions, to: .refreshing)
                .when { $0.projectInfo != nil }
                .action { args, _ in Self.prepareInspect(context: args.context, mode: .revisionsOnly) },

            Transition(on: .restore, to: .ready)
                .when { $0.projectPath.isEmpty }
                .action { args, _ in Self.applyMissingProjectMessage(to: args.context) },

            Transition(on: .restore, to: .reloading)
                .when { !$0.projectPath.isEmpty }
                .action { args, _ in Self.queueReload(context: args.context, event: args.event, mode: .fullInspect) },
        ]
    }

    private static func eventPathIsEmpty(
        _ context: ProjectContext,
        _ event: ProjectEvent?
    ) -> Bool {
        pathEventIsEmpty(event)
    }

    private static func pathEventIsEmpty(_ event: ProjectEvent?) -> Bool {
        guard case let .setPath(path)? = event else { return false }
        return path.isEmpty
    }

    private static func hasValidationError(_ context: ProjectContext) -> Bool {
        !context.projectPath.isEmpty &&
            context.projectInfo == nil &&
            context.validationMessage != nil &&
            !context.reloadPending
    }

    private static func applyEmptyPath(
        _ event: ProjectEvent?,
        to context: ProjectContext
    ) -> ProjectContext {
        var ctx = context
        guard case let .setPath(path)? = event else { return ctx }
        ctx.projectPath = path
        UserDefaults.standard.set(path, forKey: "projectPath")
        ctx.projectInfo = nil
        ctx.reloadPending = false
        ctx.validationMessage = "Choose your swift-project directory to get started."
        return ctx
    }

    private static func applyMissingProjectMessage(to context: ProjectContext) -> ProjectContext {
        var ctx = context
        ctx.projectInfo = nil
        ctx.reloadPending = false
        ctx.validationMessage = "Choose your swift-project directory to get started."
        return ctx
    }

    private static func applyBuildSubdir(
        _ event: ProjectEvent?,
        to context: ProjectContext
    ) -> ProjectContext {
        var ctx = context
        if case let .setBuildSubdir(subdir)? = event {
            ctx.selectedBuildSubdir = subdir
            UserDefaults.standard.set(subdir, forKey: "selectedBuildSubdir")
        }
        return ctx
    }

    private static func applyCheckoutScheme(
        _ event: ProjectEvent?,
        to context: ProjectContext
    ) -> ProjectContext {
        var ctx = context
        if case let .setCheckoutSchemeOverride(scheme)? = event {
            ctx.checkoutSchemeOverride = scheme
            UserDefaults.standard.set(scheme, forKey: "checkoutSchemeOverride")
        }
        return ctx
    }

    private static func prepareInspect(
        context: ProjectContext,
        mode: ProjectInspectMode
    ) -> ProjectContext {
        var ctx = context
        ctx.inspectMode = mode
        ctx.reloadPending = false
        ctx.validationMessage = nil
        return ctx
    }

    private static func clearReloadRequest(_ context: ProjectContext) -> ProjectContext {
        var ctx = context
        ctx.reloadPending = false
        ctx.validationMessage = nil
        return ctx
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
        if case let .setCheckoutSchemeOverride(scheme)? = event {
            ctx.checkoutSchemeOverride = scheme
            UserDefaults.standard.set(scheme, forKey: "checkoutSchemeOverride")
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

        next.reloadPending = false
        return next
    }
}
