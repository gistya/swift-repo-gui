import CompositionalInit
import Foundation
import SwiftXState

nonisolated enum BuildOpsState: String, StateIdentifying {
    case idle
    case running
    static var _blank: BuildOpsState { .idle }
}

nonisolated enum BuildOpsEvent: EventIdentifying {
    case start(BuildJob)
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
            XTransition(on: BuildOpsEvent.start, to: .running).action { args, _ in
                var ctx = args.context
                guard case let .start(job)? = args.event else { return ctx }
                ctx.activeJob = job
                ctx.progress = .zero
                ctx.startedAt = .now
                ctx.lastOperationID = job.operationID
                ctx.statusMessage = nil
                ctx.lastExitCode = nil
                return ctx
            }
            XTransition(on: BuildOpsEvent.setStatusMessage, to: .idle).action { args, _ in
                var ctx = args.context
                if case let .setStatusMessage(message)? = args.event { ctx.statusMessage = message }
                return ctx
            }
        }
        .initial()

        XState(.running) {
            Invoke(id: "build-process", run: { scope in
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
            })
            .input { ctx in SendableValue(ctx.activeJob) }
            .onDone(to: .idle) { (result: BuildProcessResult, ctx) in
                var next = ctx
                next.lastExitCode = result.exitCode
                next.activeJob = nil
                if result.exitCode == 0 {
                    next.progress = BuildProgressSnapshot(
                        completedSteps: max(next.progress.totalSteps, 1),
                        totalSteps: max(next.progress.totalSteps, 1),
                        fraction: 1,
                        etaSeconds: 0
                    )
                } else {
                    next.statusMessage = result.errorMessage
                }
                return next
            }
            .onError(to: .idle) { error, ctx in
                var next = ctx
                next.activeJob = nil
                next.lastExitCode = -1
                next.statusMessage = String(describing: error)
                return next
            }

            XTransition(on: BuildOpsEvent.progressUpdated, to: .running).action { args, _ in
                var ctx = args.context
                if case let .progressUpdated(snapshot)? = args.event {
                    ctx.progress = snapshot
                }
                return ctx
            }
            XTransition(on: .cancel, to: .idle).action { args, _ in
                var ctx = args.context
                ctx.activeJob = nil
                ctx.statusMessage = "Build cancelled."
                ctx.lastExitCode = -1
                return ctx
            }
        }
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