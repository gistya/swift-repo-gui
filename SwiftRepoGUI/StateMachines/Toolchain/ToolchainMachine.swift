import Foundation
import SwiftXState

/// Drives the Toolchain tab: parse the preset catalog (async, off-main) then hold the live
/// composition. The actual `build-toolchain` run reuses `BuildOperationsMachine` via `AppSession`.
struct ToolchainMachine: StateMachine {
    typealias Context = ToolchainContext
    typealias StateID = ToolchainState
    typealias EventID = ToolchainEvent

    let initialContext: ToolchainContext
    init(context: ToolchainContext = ToolchainContext()) { initialContext = context }
    var context: ToolchainContext { initialContext }

    var machine: some XStateMachine {
        State(.loading) {
            Invoke(id: "parse", run: { scope in
                guard let path = scope.input?.get(String.self), !path.isEmpty else {
                    throw PresentableError(ToolchainLoadError.missingPresetFile)
                }
                do {
                    let presets = try BuildPresetParser.parse(contentsOf: URL(fileURLWithPath: path))
                    return ToolchainCatalog(presets: presets)
                } catch {
                    throw PresentableError(ToolchainLoadError.parseFailed(error.localizedDescription))
                }
            })
            .input { ctx in SendableValue(ctx.presetFilePath) }
            .onDone(to: .ready, reading: ToolchainCatalog.self) { output, ctx in
                var next = ctx
                next.catalog = output.presets
                next.lastError = nil
                return next
            }
            .onError(to: .failed) { error, ctx in
                var next = ctx
                next.lastError = error
                return next
            }
            for transition in Self.compositionTransitions(stayingIn: .loading) { transition }
        }
        .initial()

        State(.ready) {
            for transition in Self.compositionTransitions(stayingIn: .ready) { transition }
        }

        State(.failed) {
            for transition in Self.compositionTransitions(stayingIn: .failed) { transition }
        }
    }

    private static func compositionTransitions(
        stayingIn state: ToolchainState
    ) -> [Transition] {
        [
            Transition(on: ToolchainEvent.load, to: .loading)
                .action { args, _ in
                    var ctx = args.context
                    if case let .load(path)? = args.event { ctx.presetFilePath = path }
                    return ctx
                },
            
            Transition(on: ToolchainEvent.updateDraft, to: state)
                .action { args, _ in
                    var ctx = args.context
                    if case let .updateDraft(draft)? = args.event { ctx.draft = draft }
                    return ctx
                },
            
            Transition(on: ToolchainEvent.loadRecipe, to: state)
                .action { args, _ in
                    var ctx = args.context
                    if case let .loadRecipe(draft)? = args.event { ctx.draft = draft }
                    return ctx
                },
            
            Transition(on: ToolchainEvent.newRecipe, to: state)
                .action { args, _ in
                    var ctx = args.context
                    ctx.draft = ToolchainRecipeDraft()
                    return ctx
                },
        ]
    }
}

nonisolated enum ToolchainLoadError: Error, LocalizedError, Sendable {
    case missingPresetFile
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingPresetFile: "No swift/utils/build-presets.ini — choose a swift project first."
        case let .parseFailed(message): "Could not read build-presets.ini: \(message)"
        }
    }
}
