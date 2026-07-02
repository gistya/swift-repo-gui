import CompositionalInit
import Foundation
import SwiftXState

nonisolated enum BuildOpsState: String, StateIdentifying {
    case idle
    case running
    case building
    case testing
    case measuring
    case deploying
    case completed
    case error
    case cancelled
    static var _blank: BuildOpsState { .idle }
}

nonisolated enum BuildOpsEvent: EventIdentifying {
    case start(BuildJob)
    case startRequest(BuildRunRequest)
    case cancel
    case progressUpdated(BuildProgressSnapshot)
    case setStatusMessage(String)
    static var _blank: BuildOpsEvent { .cancel }
}

nonisolated struct BuildOperationsContext: Sendable, Equatable {
    var activeJob: BuildJob?
    var progress: BuildProgressSnapshot = .zero
    var statusMessage: String?
    var lastExitCode: Int32?
    var lastOperationID: UUID?
    var startedAt: Date?

    var isRunning: Bool { activeJob != nil }
}

struct BuildOperationsMachine: StateMachine {
    typealias Context = BuildOperationsContext
    typealias StateID = BuildOpsState
    typealias EventID = BuildOpsEvent

    var context: BuildOperationsContext { .init() }

    var machine: some XStateMachine {
        XState(.idle) {
            XTransition(on: BuildOpsEvent.startRequest, to: .running).action { args, _ in
                guard case let .startRequest(request)? = args.event else { return args.context }
                return Self.start(job: BuildJobPlanner.job(for: request), context: args.context)
            }
            XTransition(on: BuildOpsEvent.start, to: .running).action { args, _ in
                guard case let .start(job)? = args.event else { return args.context }
                return Self.start(job: job, context: args.context)
            }
            XTransition(on: BuildOpsEvent.setStatusMessage, to: .error)
                .when { _, event in Self.isFailureStatusEvent(event) }
                .action { args, _ in Self.applyStatusMessage(args.event, to: args.context) }
            XTransition(on: BuildOpsEvent.setStatusMessage, to: .idle).action { args, _ in
                Self.applyStatusMessage(args.event, to: args.context)
            }
        }
        .initial()

        XState(.completed) {
            Always(to: .error)
                .when(Self.isFailureContext)
            XTransition(on: BuildOpsEvent.startRequest, to: .running).action { args, _ in
                guard case let .startRequest(request)? = args.event else { return args.context }
                return Self.start(job: BuildJobPlanner.job(for: request), context: args.context)
            }
            XTransition(on: BuildOpsEvent.start, to: .running).action { args, _ in
                guard case let .start(job)? = args.event else { return args.context }
                return Self.start(job: job, context: args.context)
            }
            XTransition(on: BuildOpsEvent.setStatusMessage, to: .error)
                .when { _, event in Self.isFailureStatusEvent(event) }
                .action { args, _ in Self.applyStatusMessage(args.event, to: args.context) }
            XTransition(on: BuildOpsEvent.setStatusMessage, to: .idle).action { args, _ in
                Self.applyStatusMessage(args.event, to: args.context)
            }
        }

        XState(.error) {
            XTransition(on: BuildOpsEvent.startRequest, to: .running).action { args, _ in
                guard case let .startRequest(request)? = args.event else { return args.context }
                return Self.start(job: BuildJobPlanner.job(for: request), context: args.context)
            }
            XTransition(on: BuildOpsEvent.start, to: .running).action { args, _ in
                guard case let .start(job)? = args.event else { return args.context }
                return Self.start(job: job, context: args.context)
            }
            XTransition(on: BuildOpsEvent.setStatusMessage, to: .error)
                .when { _, event in Self.isFailureStatusEvent(event) }
                .action { args, _ in Self.applyStatusMessage(args.event, to: args.context) }
            XTransition(on: BuildOpsEvent.setStatusMessage, to: .idle).action { args, _ in
                Self.applyStatusMessage(args.event, to: args.context)
            }
        }

        XState(.cancelled) {
            XTransition(on: BuildOpsEvent.startRequest, to: .running).action { args, _ in
                guard case let .startRequest(request)? = args.event else { return args.context }
                return Self.start(job: BuildJobPlanner.job(for: request), context: args.context)
            }
            XTransition(on: BuildOpsEvent.start, to: .running).action { args, _ in
                guard case let .start(job)? = args.event else { return args.context }
                return Self.start(job: job, context: args.context)
            }
            XTransition(on: BuildOpsEvent.setStatusMessage, to: .error)
                .when { _, event in Self.isFailureStatusEvent(event) }
                .action { args, _ in Self.applyStatusMessage(args.event, to: args.context) }
            XTransition(on: BuildOpsEvent.setStatusMessage, to: .idle).action { args, _ in
                Self.applyStatusMessage(args.event, to: args.context)
            }
        }

        XState(.running) {
            Invoke(id: "build-process", run: { scope in
                do {
                    guard let input = scope.input?.get(BuildJob.self) else {
                        throw BuildProcessFailure.missingJob
                    }
                    let sourceRoot = (input.projectPath as NSString).expandingTildeInPath
                    let buildRoot = (sourceRoot as NSString).appendingPathComponent("build")
                    return try await BuildProcessRunner.run(
                        job: input,
                        swiftSourceRoot: sourceRoot,
                        swiftBuildRoot: buildRoot
                    ) { snapshot in
                        scope.sendToParent(TypedEvent(BuildOpsEvent.progressUpdated(snapshot)))
                    }
                } catch {
                    throw PresentableError(error)
                }
            })
            .input { ctx in SendableValue(ctx.activeJob) }
            .onDone(to: .completed) { (result: BuildProcessResult, ctx) in
                var next = ctx
                next.lastExitCode = result.exitCode
                next.activeJob = nil
                if result.succeeded {
                    next.progress = BuildProgressSnapshot(
                        completedSteps: max(next.progress.totalSteps, 1),
                        totalSteps: max(next.progress.totalSteps, 1),
                        fraction: 1,
                        etaSeconds: 0,
                        message: "Finished."
                    )
                    next.statusMessage = nil
                } else {
                    next.statusMessage = result.errorMessage ?? "Build failed."
                }
                return next
            }
            .onError(to: .error) { error, ctx in
                var next = ctx
                next.activeJob = nil
                next.lastExitCode = -1
                next.statusMessage = error
                return next
            }

            XTransition(on: .cancel, to: .cancelled).action { args, _ in
                var ctx = args.context
                ctx.activeJob = nil
                ctx.statusMessage = "Build cancelled."
                ctx.lastExitCode = -1
                return ctx
            }

            XState(.building) {
                for transition in Self.progressTransitions() {
                    transition
                }
            }
            .initial()

            XState(.testing) {
                for transition in Self.progressTransitions() {
                    transition
                }
            }

            XState(.measuring) {
                for transition in Self.progressTransitions() {
                    transition
                }
            }

            XState(.deploying) {
                for transition in Self.progressTransitions() {
                    transition
                }
            }
        }
    }

    private static func progressTransitions() -> [XTransition<BuildOperationsContext, BuildOpsEvent, BuildOpsState>] {
        [
            XTransition(on: BuildOpsEvent.progressUpdated, to: .testing)
                .when { ctx, event in Self.stage(for: event, context: ctx) == .testing }
                .action { args, _ in Self.applyProgress(args.event, to: args.context) },
            XTransition(on: BuildOpsEvent.progressUpdated, to: .measuring)
                .when { ctx, event in Self.stage(for: event, context: ctx) == .measuring }
                .action { args, _ in Self.applyProgress(args.event, to: args.context) },
            XTransition(on: BuildOpsEvent.progressUpdated, to: .deploying)
                .when { ctx, event in Self.stage(for: event, context: ctx) == .deploying }
                .action { args, _ in Self.applyProgress(args.event, to: args.context) },
            XTransition(on: BuildOpsEvent.progressUpdated, to: .building)
                .action { args, _ in Self.applyProgress(args.event, to: args.context) },
        ]
    }

    private static func start(job: BuildJob, context: BuildOperationsContext) -> BuildOperationsContext {
        var ctx = context
        ctx.activeJob = job
        ctx.progress = BuildProgressSnapshot(
            completedSteps: 0,
            totalSteps: 0,
            fraction: 0,
            etaSeconds: nil,
            message: "Starting: \(job.displayCommand)"
        )
        ctx.startedAt = .now
        ctx.lastOperationID = job.operationID
        ctx.statusMessage = nil
        ctx.lastExitCode = nil
        return ctx
    }

    private static func applyProgress(
        _ event: BuildOpsEvent?,
        to context: BuildOperationsContext
    ) -> BuildOperationsContext {
        var ctx = context
        if case let .progressUpdated(snapshot)? = event {
            ctx.progress = snapshot
        }
        return ctx
    }

    private static func applyStatusMessage(
        _ event: BuildOpsEvent?,
        to context: BuildOperationsContext
    ) -> BuildOperationsContext {
        var ctx = context
        if case let .setStatusMessage(message)? = event {
            ctx.statusMessage = message
            ctx.lastExitCode = isFailureStatus(message) ? -1 : ctx.lastExitCode
        }
        return ctx
    }

    private static func stage(
        for event: BuildOpsEvent?,
        context: BuildOperationsContext
    ) -> BuildStage {
        guard case let .progressUpdated(snapshot)? = event else {
            return BuildStage.stage(for: context)
        }
        return BuildStage.runningStage(for: context.activeJob, progress: snapshot)
    }

    private static func isFailureStatusEvent(_ event: BuildOpsEvent?) -> Bool {
        guard case let .setStatusMessage(message)? = event else { return false }
        return isFailureStatus(message)
    }

    private static func isFailureStatus(_ message: String) -> Bool {
        let status = message.lowercased()
        return status.contains("failed") || status.contains("error")
    }

    private static func isFailureContext(_ context: BuildOperationsContext) -> Bool {
        if let exitCode = context.lastExitCode, exitCode != 0 { return true }
        if let message = context.statusMessage {
            return isFailureStatus(message)
        }
        return false
    }
}

enum BuildProcessFailure: Error, CustomStringConvertible {
    case missingJob
    var description: String {
        switch self {
        case .missingJob: "No build job was provided to the runner."
        }
    }
}
